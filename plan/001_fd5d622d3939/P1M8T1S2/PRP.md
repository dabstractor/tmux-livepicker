# PRP — P1.M8.T1.S2: CHANGELOG / version note + recommend PRD §0 removal

---

## Goal

**Feature Goal**: **CREATE** the repo-root `CHANGELOG.md` for tmux-livepicker — the Mode B
"sync changeset-level documentation" **sibling deliverable** to the README (S1). It is the
canonical home for the initial-implementation record, the **three proven architectural
invariants** that the implementation upholds, the **documented tmux floor correction
(3.2, not the PRD's 3.0 guess)**, and the **explicit human-only recommendation to remove
PRD §0** once the PRD §15 validation suite passes on the real environment. It records a
recommendation the implementation is forbidden from enacting (the SOW forbids editing
`PRD.md`), so the §0 instruction does not silently disappear.

**Deliverable** (ONE new file): `CHANGELOG.md` at the repo root
(`/home/dustin/.config/tmux/plugins/tmux-livepicker/CHANGELOG.md`). Markdown, keepachangelog
format (concise, in the spirit of the only sibling that has one — `tmux-resurrect/CHANGELOG.md`),
newest-first, with exactly these blocks: title + format line → `## [Unreleased] — Initial
implementation` → `### Added` (initial implementation + the three invariants) →
`### Documented corrections` (floor 3.2) → `### Notes for maintainers` (PRD §0 removal).

**Success Definition**:
- `CHANGELOG.md` exists at repo root; renders as well-formed Markdown (one `#` H1; balanced
  fenced blocks; consistent heading levels; newest-first).
- **Every factual claim is verifiably accurate** (Validation Level 3 checks each): the three
  invariants match `architecture/system_context.md` §3 A/B/C verbatim in meaning; the floor
  correction states **3.2** and references the PRD's **3.0** as the corrected value; the
  validation reference is exactly `bash tests/run.sh`; the §0 recommendation names the
  **human** actor and the **real-environment §15** trigger, and notes `PRD.md` is READ-ONLY.
- `git diff --stat` shows ONLY `CHANGELOG.md` added by THIS task (NO edits to PRD.md,
  tasks.json, prd_snapshot.md, .gitignore, any `scripts/*` or `tests/*`, and NO README.md —
  that is sibling task **P1.M8.T1.S1**).

## User Persona

**Target User**: (1) a maintainer / future contributor reading what shipped in the initial
build and why the design holds (the three invariants); (2) a maintainer deciding whether it
is safe to remove PRD §0; (3) a packager/release-note reader checking the tmux floor and any
documented corrections. The CHANGELOG is a build/maintenance record (DOCS: this IS the docs
task — Mode B).

**Use Case**: a maintainer opens `CHANGELOG.md`, reads the initial-implementation entry,
confirms the three load-bearing invariants are documented (so a future refactor does not
silently break them), notes the floor was corrected to 3.2, and follows the "Notes for
maintainers" action (remove PRD §0) once the §15 suite passes on the real machine.

**User Journey**: open CHANGELOG.md → scan `## [Unreleased]` → read the three invariants
(trust the design) → read the floor correction (know the real requirement) → see the
maintainer note (act on §0 after verification).

**Pain Points Addressed**: without this file, the §0 self-removal instruction is lost (the
implementation cannot edit PRD.md), the three proven invariants live only in a deep
architecture doc (invisible to a casual maintainer), and the 3.0→3.2 floor correction has no
durable record — risking a future contributor re-introducing the prior-attempt bug or
re-asserting the wrong floor.

## Why

- **PRD §0** ("Prior attempt") self-instructs: *"After the implementation lands and is
  verified, remove this entire section on the next edit."* The SOW FORBIDDEN OPERATIONS list
  forbids automated agents from editing `PRD.md`. **Resolution** (`<item_description>` §1):
  record the recommendation in a CHANGELOG entry and surface it in the README. This task owns
  the CHANGELOG record (S1's README only surfaces/points to it).
- **PRD §1** (Overview), **§15** (Validation), and **§16** (Implementation risks, incl. the
  stale `tmux 3.0` floor) are the source content (selected via PRD selectors `h2.0,h2.1,h2.16`).
- **Scope cohesion.** P1.M8 is "Sync changeset-level documentation (Mode B)". S1 owns the
  README; **P1.M8.T1.S2** owns the CHANGELOG + the PRD §0-removal recommendation's canonical
  home. S1's README "Maintenance" note POINTS to this CHANGELOG. To avoid conflict, S2 writes
  ONLY `CHANGELOG.md`.
- **Context is king.** A CHANGELOG that copied the PRD's `tmux 3.0` floor, or that omitted
  the three invariants, or that claimed §0 was already removed, would be wrong. This PRP
  supplies the **verified** facts (architecture `system_context.md` §3 the three invariants;
  §10 floor 3.2) so the CHANGELOG is a correct, durable record, not a copy of PRD aspirations.

## What

**CREATE** `CHANGELOG.md` at repo root. Structure (keepachangelog format, newest-first):

1. **Title + format line** — `# Changelog` H1; a one-line note that all notable changes are
   documented here and the format follows [Keep a Changelog](https://keepachangelog.com/).
2. **`## [Unreleased] — Initial implementation`** — the single entry; the plugin is built but
   no version tag exists (`git tag` is empty; this is the initial build P1.M1–M7). Do NOT
   invent a semver tag.
3. **`### Added`** — two blocks:
   - The **initial implementation** of the plugin, built end-to-end from the PRD (modal
     status-line session/window picker; live, in-place, all-panes preview), spanning P1.M1–M7
     (options, utils, state, entry point, renderer, preview, activate/restore orchestration,
     input handler) plus the isolated-socket test harness. Reference `bash tests/run.sh`.
   - **The three load-bearing architectural invariants** (PROVEN during research; upheld by
     the implementation). List them as a numbered sub-list with bold leads, matching
     `architecture/system_context.md` §3 A/B/C exactly in meaning:
     1. **Browsing never fires `client-session-changed`** — preview uses `link-window` +
        `select-window` (not `switch-client`); only the single confirm-time `switch-client`
        fires `client-session-changed`, so the tmux-session-history timeline and the
        `@session-history-prev` toggle are untouched while browsing. (PRD §4 / §14.)
     2. **A non-root `key-table` is fully modal** — while the `livepicker` table is active,
        tmux consults only it; unmatched keys are dropped, never passed to the previewed pane,
        so the preview is genuinely display-only. (PRD §7 / §8.)
     3. **Multi-line status composes correctly** — with `status=2`, `status-format[0]` set to
        `#(renderer.sh)` (picker) and `status-format[1]` unset, line 1 is the picker and line 2
        is tmux's live-composed default (the user's normal window-status line). (PRD §10.)
4. **`### Documented corrections`** — the **tmux floor correction to 3.2**. State: the PRD §16
   named `3.0` as the floor; verified research established that the genuinely binding feature
   — **multi-line `status` / `status-format[n]`** — was introduced in **3.2**, so the
   documented floor is **3.2** (not the PRD's 3.0). Tested on tmux **3.6b**. Reference
   `plan/001_fd5d622d3939/architecture/system_context.md` §10 as the authority.
5. **`### Notes for maintainers`** — the **PRD §0 removal** recommendation. State: PRD §0
   ("Prior attempt") is a build-time scaffold whose last paragraph instructs removing it
   *"after the implementation lands and is verified."* The SOW forbids automated tools from
   editing `PRD.md`, so the implementation left it intact. **Human action:** once the full
   PRD §15 validation suite passes on the **real environment** (beyond the isolated
   `bash tests/run.sh` socket harness — a human confirms §15 on the live machine), remove
   PRD §0 by hand. This CHANGELOG entry records the recommendation; the README (S1)
   "Validation"/"Maintenance" section surfaces it. Note that `PRD.md` is READ-ONLY to agents.

### Success Criteria

- [ ] `CHANGELOG.md` exists at repo root with the 5 structural blocks above.
- [ ] The three invariants are present and match `architecture/system_context.md` §3 A/B/C
      (no client-session-changed while browsing; modal key-table; multi-line status composition).
- [ ] The floor correction states **3.2** (corrected from the PRD's **3.0**), tested **3.6b**.
- [ ] The §0 recommendation names the **human** actor + **real-environment §15** trigger,
      and notes `PRD.md` is READ-ONLY (not edited by this task).
- [ ] The validation reference is exactly `bash tests/run.sh`.
- [ ] `git diff --stat` shows ONLY `CHANGELOG.md` added by this task.

## All Needed Context

### Context Completeness Check

_Pass_: a writer who has never seen this repo can produce a correct CHANGELOG from (a) the
ready-to-paste block skeletons in "Implementation Patterns & Key Details"; (b) the verified
facts in `research/changelog_findings.md` (8 findings) and `architecture/system_context.md`
§3/§10; and (c) the sibling style template (`../tmux-resurrect/CHANGELOG.md`). No guessing is
required — every invariant, version, command, and recommendation is pinned below.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth for THIS task (8 findings + the CHANGELOG skeleton).
- docfile: plan/001_fd5d622d3939/P1M8T1S2/research/changelog_findings.md
  why: F1 (Mode B sibling to README/S1; produces ONLY CHANGELOG.md, non-conflicting); F2
        (style: keepachangelog categories + resurrect concision; ONE sibling has a CHANGELOG);
        F3 (no git tag -> Unreleased, initial implementation; do NOT invent semver); F4 (the
        three invariants verbatim A/B/C); F5 (floor 3.2 NOT 3.0, tested 3.6b, why); F6 (§0
        removal is a HUMAN action, SOW forbids PRD.md edits, real-env §15 trigger); F7
        (validation = bash tests/run.sh + §15 clusters, test files present); F8 (scope: ONLY
        CHANGELOG.md; do not touch PRD.md/scripts/tests/README).
  critical: Read BEFORE writing. F4 (invariants) and F5 (floor) are the two most likely
        accuracy errors.

# MUST READ — the architectural ground-truth (verified facts, authoritative over the PRD).
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §3 (the THREE proven invariants A/B/C — copy their meaning verbatim into the Added
        block); §10 (version floor: "binding feature is multi-line status ... introduced in
        3.2 ... Recommend documenting the floor as 3.2"; tested 3.6b — the authority for the
        floor-correction entry). §11 cross-refs to tmux_primitives / sibling_plugins.
  section: "§3", "§10".

# MUST READ — the PRD sections selected for this work item (the content + correction source).
- docfile: PRD.md
  why: §0 (the "Prior attempt" scaffold + its self-removal instruction "After the
        implementation lands and is verified, remove this entire section on the next edit" —
        the basis of the Notes-for-maintainers entry); §1 (Overview — the one-line plugin
        description for the initial-implementation bullet); §16 (Implementation risks — the
        stale "tmux floor ... 3.0 ... Target 3.0 as the floor; test on the installed 3.6b"
        sentence that the floor-correction entry corrects). §15 (the validation clusters that
        gate §0 removal).
  critical: PRD §16 says "3.0" — this is the PRD's UNVERIFIED guess. The CHANGELOG MUST record
        the correction to 3.2 (architecture §10). Do NOT re-assert 3.0 as correct. Do NOT edit
        PRD.md to "fix" it — the CHANGELOG documents the correction instead.

# MUST READ — the sibling style contract (the ONLY sibling that ships a CHANGELOG).
- file: ../tmux-resurrect/CHANGELOG.md
  why: the cleanest extant CHANGELOG among the siblings. Style to mirror: `# Changelog` H1;
        version/`master` headers newest-first; concise one-line present-tense bullets. Add
        keepachangelog categories (Added / Documented corrections / Notes for maintainers) on
        top of that concision — they read better for the correction + invariant + maintainer
        content than resurrect's flat bullet list.
  pattern: newest-first; one H1; short bullets; no prose walls.

# READ — the README (sibling S1) being built in parallel, to keep the two docs consistent.
- docfile: plan/001_fd5d622d3939/P1M8T1S1/PRP.md   # (README PRP; README.md may not exist yet)
  why: S1's README adds a short "Maintenance" note that POINTS to this CHANGELOG and also
        recommends §0 removal. The CHANGELOG is the canonical home; the README surfaces it.
        Ensure the two agree on: floor = 3.2; §0 removal is human + post-real-verification;
        validation command = bash tests/run.sh. Do NOT duplicate the whole recommendation in
        both — the CHANGELOG is authoritative, the README is a pointer.

# READ — the test runner (the validation reference cited in the CHANGELOG).
- file: tests/run.sh
  why: the entry point the CHANGELOG references as `bash tests/run.sh`. CONFIRMED COMPLETE:
        sources setup_socket.sh + helpers.sh + every tests/test_*.sh; discovers test_*;
        fresh isolated socket per test; exits 0 iff all pass. The §15 clusters it covers:
        functional (§15.17), pollution (§15.18), preview (§15.19), key-repurpose (§15.20),
        restore (§15.21), create-on-enter (§15.22).
  gotcha: reference the COMMAND, not a test count (count is stable now but the command is the
        durable contract).
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md                  # READ-ONLY (FORBIDDEN to edit). §0 / §1 / §15 / §16 are sources.
  plugin.tmux             # COMPLETE. (referenced indirectly; entry point.)
  scripts/                # ALL COMPLETE (P1.M1-M6). options/utils/state/filter/renderer/
                          #   preview/livepicker/restore/input-handler.
  tests/                  # P1.M7. run.sh is the validation command.
    setup_socket.sh helpers.sh run.sh           # COMPLETE harness.
    test_self.sh test_functional.sh test_preview.sh test_pollution.sh     # COMPLETE.
    test_restore.sh test_keyrepurpose.sh test_create.sh                   # COMPLETE.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M8T1S1/{PRP.md, research/readme_findings.md}    # sibling (README).
  plan/001_fd5d622d3939/P1M8T1S2/{PRP.md, research/changelog_findings.md} # THIS.
  ../tmux-resurrect/CHANGELOG.md   # the style template (only sibling with a CHANGELOG).
  .gitignore
  # NOTE: CHANGELOG.md does NOT exist yet — THIS task creates it. README.md is created by
  #   sibling S1 in parallel (do not create it). No LICENSE exists (do not create one).
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  CHANGELOG.md   # NEW. The maintenance/release record for the initial implementation.
                 #   # Changelog (H1) + keepachangelog format line.
                 #   ## [Unreleased] — Initial implementation
                 #     ### Added
                 #       - initial implementation of tmux-livepicker (P1.M1-M7) per PRD;
                 #         reference `bash tests/run.sh`.
                 #       - the THREE proven invariants (A: no client-session-changed while
                 #         browsing; B: modal key-table drops unmatched keys; C: multi-line
                 #         status composes correctly) — verbatim meaning from arch §3.
                 #     ### Documented corrections
                 #       - tmux floor corrected to 3.2 (multi-line status is the binding
                 #         feature; PRD §16 said 3.0); tested on 3.6b — arch §10.
                 #     ### Notes for maintainers
                 #       - PRD §0 removal: human action, after PRD §15 passes on the REAL
                 #         environment; PRD.md is READ-ONLY to agents; README (S1) points here.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (do NOT edit PRD.md): the SOW FORBIDDEN OPERATIONS list forbids editing PRD.md
#   (READ-ONLY). The §0-removal instruction in PRD §0 is RECORDED here as a human
#   recommendation — never enacted by this task. State explicitly that PRD.md is read-only.

# CRITICAL (floor = 3.2, NOT 3.0): the CHANGELOG documents the CORRECTION. PRD §16 says "3.0"
#   (unverified guess). architecture system_context §10 (authoritative) names multi-line
#   status/status-format[n] as the binding feature, introduced in 3.2; tested on 3.6b.
#   `tmux -V` == 3.6b. The entry must say "corrected to 3.2" and cite the PRD's 3.0 as the
#   value being corrected. Do NOT re-assert 3.0 as the floor.

# CRITICAL (the three invariants are PROVEN, not aspirational): copy their MEANING verbatim
#   from architecture/system_context.md §3 A/B/C. They are the spine of the design and the
#   reason the prior attempt failed (it switched-client per keystroke -> fired
#   client-session-changed -> shredded history + toggle). Naming them in the CHANGELOG makes a
#   future refactor think twice before breaking them.

# GOTCHA (no semver tag): `git tag` is empty. This is the initial implementation, unreleased.
#   Use `## [Unreleased] — Initial implementation`. Do NOT invent v1.0.0 / v0.1.0.

# GOTCHA (validation trigger nuance): the §0-removal trigger is "PRD §15 passes on the REAL
#   environment" — i.e. a human verifies beyond the isolated `bash tests/run.sh` socket
#   harness (which is already green). State BOTH: `bash tests/run.sh` is the automated gate,
#   AND a human confirms §15 on the live machine before removing §0. The isolated harness
#   cannot itself authorize editing PRD.md.

# GOTCHA (no README duplication): S1's README "Maintenance" note POINTS to this CHANGELOG and
#   briefly recommends §0 removal. This CHANGELOG is the canonical, detailed record. Keep them
#   consistent (floor 3.2; human + post-real-verification; bash tests/run.sh) but do not
#   copy the entire recommendation into both.

# STYLE: Markdown. `# Changelog` H1; keepachangelog categories (Added / Documented corrections
#   / Notes for maintainers); newest-first; concise bullets (mirror ../tmux-resurrect/CHANGELOG.md
#   brevity). Reference paths are relative to repo root for repo files
#   (plan/001_fd5d622d3939/architecture/system_context.md) — they are accurate from repo root.
```

## Implementation Blueprint

### Data models and structure

No data model. The "model" is the **CHANGELOG block map**:

```markdown
# Changelog                                           <- H1 + keepachangelog format line
## [Unreleased] — Initial implementation              <- single entry (no git tag exists)
  ### Added                                           <- (1) initial implementation (P1.M1-M7);
                                                      <- (2) the THREE proven invariants A/B/C.
  ### Documented corrections                          <- tmux floor 3.2 (corrected from PRD's 3.0).
  ### Notes for maintainers                           <- PRD §0 removal: human + real-env §15.
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE CHANGELOG.md — title + format line + the [Unreleased] / Added (initial impl) block
  - CREATE: CHANGELOG.md (NEW; repo root).
  - TITLE: `# Changelog` + a one-line format note: "All notable changes to tmux-livepicker are
        documented here. Format based on [Keep a Changelog](https://keepachangelog.com/)."
  - HEADER: `## [Unreleased] — Initial implementation` (NO semver tag: `git tag` is empty; this
        is the initial build P1.M1-M7).
  - ADDED (first bullet): the initial implementation of the plugin, built end-to-end from the
        PRD — a modal status-line session/window picker with live, in-place, all-panes preview —
        spanning P1.M1-M7 (options, utils, state, entry point, renderer, preview, activate/restore
        orchestration, input handler) plus the isolated-socket test harness. One sentence; reference
        `bash tests/run.sh` as the way to validate.
  - FOLLOW style: ../tmux-resurrect/CHANGELOG.md (concise; one H1; newest-first).

Task 2: APPEND the three proven invariants to the Added block
  - ADDED (second bullet, with a numbered sub-list): "The three load-bearing architectural
        invariants, proven during research and upheld by the implementation:" then:
        1. **Browsing never fires `client-session-changed`.** Preview uses `link-window` +
           `select-window` (NOT `switch-client`); only the single confirm-time `switch-client`
           fires `client-session-changed`, so the tmux-session-history timeline and the
           `@session-history-prev` toggle are untouched while browsing. (PRD §4 / §14.)
        2. **A non-root `key-table` is fully modal.** While the `livepicker` table is active,
           tmux consults only it; unmatched keys are dropped, never passed to the previewed pane,
           so the preview is genuinely display-only. (PRD §7 / §8.)
        3. **Multi-line status composes correctly.** With `status=2`, `status-format[0]` set to
           `#(renderer.sh)` (picker) and `status-format[1]` unset, line 1 is the picker and line 2
           is tmux's live-composed default (the user's normal window-status line). (PRD §10.)
  - ACCURACY: copy the MEANING verbatim from architecture/system_context.md §3 A/B/C. These are
        PROVEN facts; do not hedge ("may"/"should"). This block is why the CHANGELOG exists.

Task 3: APPEND the Documented corrections block (floor 3.2)
  - HEADER: `### Documented corrections`
  - BULLET: "**tmux version floor corrected to 3.2.** The PRD §16 named `3.0` as the floor;
        verified research established that the genuinely binding feature — multi-line `status` /
        `status-format[n]` — was introduced in **3.2**, so the documented floor is **3.2** (not the
        PRD's `3.0`). Tested on tmux **3.6b** (`tmux -V`). See
        `plan/001_fd5d622d3939/architecture/system_context.md` §10."
  - ACCURACY: state BOTH the corrected value (3.2) AND the corrected-FROM value (PRD's 3.0), so
        the correction is unambiguous. Do NOT re-assert 3.0 as correct.

Task 4: APPEND the Notes for maintainers block (PRD §0 removal)
  - HEADER: `### Notes for maintainers`
  - BULLET: "**PRD §0 removal.** PRD §0 ("Prior attempt") is a build-time scaffold whose final
        paragraph instructs removing it *after the implementation lands and is verified.* The
        implementation's SOW forbids automated tools from editing `PRD.md`, so §0 was left intact.
        **Action for a human maintainer:** once the full PRD §15 validation suite passes on the
        **real environment** (a human confirms §15 on the live machine, beyond the isolated
        `bash tests/run.sh` socket harness), remove PRD §0 by hand. This entry records the
        recommendation; the README (sibling task P1.M8.T1.S1) surfaces it in its
        Validation/Maintenance section."
  - ACCURACY: name the HUMAN actor and the REAL-ENVIRONMENT §15 trigger explicitly; state
        PRD.md is READ-ONLY to agents (so a reader understands why this is a recommendation,
        not a done edit).

Task 5: VALIDATE (Level 1 markdown + Level 3 accuracy cross-checks + Level 4 tests still green)
  - RUN: a markdown lint/render check (e.g. `markdownlint CHANGELOG.md` if available, else
        eyeball a render); the Level 3 accuracy greps (three invariants present; floor 3.2 + the
        3.0 correction; §0 recommendation names human + real-env; validation = bash tests/run.sh;
        PRD.md read-only stated); confirm `bash tests/run.sh` is unaffected by the doc change
        (it should still pass — CHANGELOG adds no code).
  - ASSERT: `git diff --stat` shows ONLY `CHANGELOG.md` added by this task (README.md may also
        appear from parallel S1 — that is expected and non-overlapping).
```

### Implementation Patterns & Key Details

#### Verbatim CHANGELOG skeleton (copy, then fill the pinned values)

```markdown
# Changelog

All notable changes to tmux-livepicker are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/).

## [Unreleased] — Initial implementation

### Added

- Initial implementation of tmux-livepicker, built end-to-end from the PRD: a modal
  status-line session and window picker that previews candidates live, in place, without
  leaving the current session. Spans P1.M1–M7 (options, utils, state, entry point, renderer,
  live preview, activate/restore orchestration, input handler) plus an isolated-socket test
  harness. Validate with `bash tests/run.sh`.
- The three load-bearing architectural invariants, proven during research and upheld by the
  implementation:
  1. **Browsing never fires `client-session-changed`.** The preview uses `link-window` +
     `select-window` (not `switch-client`); only the single confirm-time `switch-client` fires
     `client-session-changed`, so the tmux-session-history timeline and the
     `@session-history-prev` toggle are untouched while browsing. (PRD §4 / §14.)
  2. **A non-root `key-table` is fully modal.** While the `livepicker` table is active, tmux
     consults only it; unmatched keys are dropped, never passed to the previewed pane, so the
     preview is genuinely display-only. (PRD §7 / §8.)
  3. **Multi-line status composes correctly.** With `status=2`, `status-format[0]` set to
     `#(renderer.sh)` (the picker) and `status-format[1]` unset, line 1 is the picker and line 2
     is tmux's live-composed default (the user's normal window-status line). (PRD §10.)

### Documented corrections

- **tmux version floor corrected to 3.2.** The PRD §16 named `3.0` as the floor; verified
  research established that the genuinely binding feature — multi-line `status` /
  `status-format[n]` — was introduced in **3.2**, so the documented floor is **3.2** (not the
  PRD's `3.0`). Tested on tmux **3.6b** (`tmux -V`). See
  `plan/001_fd5d622d3939/architecture/system_context.md` §10.

### Notes for maintainers

- **PRD §0 removal.** PRD §0 ("Prior attempt") is a build-time scaffold whose final paragraph
  instructs removing it *after the implementation lands and is verified.* The implementation's
  SOW forbids automated tools from editing `PRD.md`, so §0 was left intact. **Action for a human
  maintainer:** once the full PRD §15 validation suite passes on the **real environment** (a
  human confirms §15 on the live machine, beyond the isolated `bash tests/run.sh` socket
  harness), remove PRD §0 by hand. This entry records the recommendation; the README (sibling
  task P1.M8.T1.S1) surfaces it in its Validation/Maintenance section.
```

### Integration Points

```yaml
FILES (touched):
  - create: "CHANGELOG.md"   # repo root. The ONLY file this task produces.

FILES (read-only references, do NOT edit):
  - PRD.md                                  # §0 / §1 / §15 / §16 are sources. READ-ONLY.
  - plan/001_fd5d622d3939/architecture/system_context.md   # §3 (invariants), §10 (floor).
  - tests/run.sh                            # the validation command referenced in the entry.
  - ../tmux-resurrect/CHANGELOG.md          # the STYLE template.

CROSS-DOC CONSISTENCY (sibling S1 README.md, built in parallel):
  - floor is 3.2 in BOTH the CHANGELOG and the README.
  - §0 removal is a human + post-real-verification action in BOTH; the README POINTS here.
  - validation command is `bash tests/run.sh` in BOTH.

NO CODE CHANGES:
  - The CHANGELOG adds no code. `bash tests/run.sh` is unaffected and must still pass.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Markdown well-formedness (pick one available; else eyeball a render).
markdownlint CHANGELOG.md 2>/dev/null || true   # if markdownlint is installed
# OR render-check: `glow CHANGELOG.md` if available.

# Structural sanity (no tool needed):
grep -c '^# Changelog' CHANGELOG.md            # expect 1 (exactly one H1)
grep -c '^## \[Unreleased\]' CHANGELOG.md     # expect 1 (the single entry header)
grep -c '^### ' CHANGELOG.md                   # expect 3 (Added / Documented corrections / Notes for maintainers)
# Expected: one H1; one Unreleased header; exactly three ### category blocks; balanced fences.
```

### Level 2: Render / Link Check (Component Validation)

```bash
# The keepachangelog link is well-formed and the architecture reference path is accurate.
grep -n 'keepachangelog.com' CHANGELOG.md                                 # format link present
test -f plan/001_fd5d622d3939/architecture/system_context.md \
  && echo "arch ref path valid" || echo "MISMATCH: arch path wrong"
grep -n 'system_context.md' CHANGELOG.md                                  # arch §10 ref present
# Expected: link + path valid; the entry references the architecture authority for the floor.
```

### Level 3: Accuracy Cross-Checks (the core gate — every claim matches verified facts)

```bash
# (a) The THREE invariants are present (meaning verbatim from arch §3 A/B/C).
grep -qi 'client-session-changed' CHANGELOG.md && echo "A present"
grep -qi 'modal' CHANGELOG.md && grep -qi 'key-table\|key table' CHANGELOG.md && echo "B present"
grep -qi 'multi-line status\|multi-line `status`\|status-format' CHANGELOG.md && echo "C present"

# (b) The floor correction states 3.2 AND names the PRD's 3.0 as the corrected value.
grep -E '3\.2' CHANGELOG.md && echo "floor 3.2 present"
grep -Ei 'PRD .*3\.0|3\.0.*PRD' CHANGELOG.md && echo "3.0-as-corrected named"
# Cross-check the authority: arch §10 is the source of 3.2.
grep -E 'introduced in 3.2|documenting the floor as 3.2' plan/001_fd5d622d3939/architecture/system_context.md

# (c) The §0 recommendation names the HUMAN actor + REAL-ENVIRONMENT trigger + read-only note.
grep -Ei 'human|maintainer' CHANGELOG.md && echo "human actor named"
grep -Ei 'real environment|live machine' CHANGELOG.md && echo "real-env trigger present"
grep -Ei 'READ-ONLY|read.only|forbids.*PRD' CHANGELOG.md && echo "read-only note present"

# (d) The validation reference is exactly bash tests/run.sh.
grep -F 'bash tests/run.sh' CHANGELOG.md && echo "validation command present"

# (e) No forbidden edits; ONLY CHANGELOG.md added by THIS task.
git diff --stat -- CHANGELOG.md            # CHANGELOG.md should appear
git diff --name-only | grep -E 'PRD.md|tasks.json|prd_snapshot.md|.gitignore|^scripts/|^tests/' \
  && echo "ERROR: forbidden file edited" || echo "scope clean"
# Expected: CHANGELOG.md only (README.md may also appear from parallel S1 — that is expected).
# Confirm no README/LICENSE was created by THIS task (S1 owns README; LICENSE is out of scope).
# (README.md existing is fine — it is sibling S1's deliverable.)
```

### Level 4: Documentation / Regression Validation

```bash
# The CHANGELOG adds NO code, so the test suite must be unaffected and still green.
bash tests/run.sh
# Expected: same PASS/FAIL outcome as before this task (exits 0 iff all pass). The CHANGELOG
# must not change any script or test. If run.sh now fails, a script/test was accidentally
# edited — revert it (FORBIDDEN).

# Confirm PRD.md was NOT edited (READ-ONLY; the §0 recommendation must be a recommendation,
# not an enacted edit).
git diff --quiet -- PRD.md && echo "PRD.md untouched (correct)" || echo "ERROR: PRD.md edited"
# Expected: PRD.md untouched.

# Cross-doc consistency with the sibling README (if it exists yet from parallel S1):
# both should state floor 3.2 and reference bash tests/run.sh.
if [ -f README.md ]; then
  grep -E 'tmux .*3\.2' README.md >/dev/null && echo "README floor consistent" || echo "note: README floor differs (S1 may still be in progress)"
fi
```

## Final Validation Checklist

### Technical Validation

- [ ] All 4 validation levels completed successfully.
- [ ] Level 1: CHANGELOG renders as well-formed Markdown (one H1; one Unreleased header; three
      ### category blocks; balanced fences).
- [ ] Level 3 (a): the three invariants present (client-session-changed; modal key-table;
      multi-line status) matching architecture §3.
- [ ] Level 3 (b): floor stated as **3.2**, with the PRD's **3.0** named as the corrected value;
      arch §10 is the cited authority.
- [ ] Level 3 (c): §0 recommendation names the **human** actor + **real-environment §15** trigger
      + notes `PRD.md` is READ-ONLY.
- [ ] Level 3 (d): validation reference is exactly `bash tests/run.sh`.
- [ ] Level 3 (e): `git diff --stat` shows ONLY `CHANGELOG.md` added by this task.
- [ ] Level 4: `bash tests/run.sh` unaffected (CHANGELOG adds no code); PRD.md untouched.

### Feature Validation

- [ ] All 5 structural blocks present (title+format line; [Unreleased]/Added initial impl; Added
      invariants; Documented corrections; Notes for maintainers).
- [ ] The initial-implementation bullet references `bash tests/run.sh` and spans P1.M1–M7.
- [ ] The three invariants are numbered and bold-led, matching arch §3 A/B/C.
- [ ] The floor-correction entry cites the architecture authority and the tested version (3.6b).
- [ ] The §0-recommendation entry explains WHY it is a recommendation (SOW forbids PRD.md edits).

### Code Quality Validation

- [ ] Follows the concise sibling style of `tmux-resurrect/CHANGELOG.md` (newest-first; short bullets).
- [ ] No generic references — all versions/invariants/commands/paths are specific and verified.
- [ ] Consistent heading levels; keepachangelog categories used.
- [ ] Anti-patterns avoided (see below).

### Documentation & Deployment

- [ ] Cross-doc consistency with the sibling README (floor 3.2; bash tests/run.sh; §0 = human +
      post-real-verification) — the README points here.
- [ ] No claim contradicts the architecture ground-truth or the shipped code.

---

## Anti-Patterns to Avoid

- ❌ Don't edit `PRD.md` to "remove §0" or to "fix the 3.0 floor" — both are FORBIDDEN. The
  CHANGELOG **records** the §0-removal recommendation and **documents** the floor correction; it
  never enacts either against PRD.md.
- ❌ Don't re-assert tmux 3.0 as the floor — the verified binding feature is multi-line `status`
  (≥ 3.2); 3.6b is the tested target. The PRD's "3.0" is the value being corrected.
- ❌ Don't hedge the three invariants ("may"/"should") — they are PROVEN (architecture §3). State
  them as fact.
- ❌ Don't invent a semver tag (v1.0.0 / v0.1.0) — `git tag` is empty; use `## [Unreleased]`.
- ❌ Don't conflate the isolated `bash tests/run.sh` gate with the §0-removal trigger — the trigger
  is a HUMAN confirming §15 on the REAL environment (beyond the isolated harness).
- ❌ Don't create README.md (sibling P1.M8.T1.S1 owns it), LICENSE (out of scope), or any
  scripts/tests/PRD.md/tasks.json/prd_snapshot.md/.gitignore edits.
- ❌ Don't duplicate the full §0 recommendation into both the README and the CHANGELOG — the
  CHANGELOG is canonical; the README is a pointer.
- ❌ Don't copy the prior-attempt failure story verbatim into the CHANGELOG as if it were a feature
  — reference it only as context for invariant A (why switch-client-per-keystroke was fatal).
