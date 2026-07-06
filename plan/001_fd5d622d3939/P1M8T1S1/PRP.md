# PRP — P1.M8.T1.S1: `README.md` — overview, install, config table, usage, compatibility

---

## Goal

**Feature Goal**: **CREATE** the repo-root `README.md` for tmux-livepicker — the Mode B
"sync changeset-level documentation" catch-all (SOW §5). It runs LAST and must reflect
the **SHIPPED** behavior of the COMPLETE plugin (P1.M1–M6) and the COMPLETE test suite
(P1.M7), not PRD aspirations. It is the single user-facing document: it tells a new user
what the plugin is, how to install it (two paths), how to configure every `@livepicker-*`
option (the full PRD §11 table with verified defaults), how to drive it (the prefix-table
activation flow), how it previews without switching sessions (the one invariant), what tmux
versions it supports, how it composes with sibling plugins, and how to run `bash tests/run.sh`.

**Deliverable** (ONE new file): `README.md` at the repo root
(`/home/dustin/.config/tmux/plugins/tmux-livepicker/README.md`). Markdown, modeled on the
concise sibling style of `tmux-session-history/README.md` (the closest composition target),
with exactly the sections named in the work-item §3: **Overview, Goals/non-goals, User
stories, Installation, Configuration, Usage, How it works, Compatibility, Validation**
(plus a short Maintenance note for the PRD §0 recommendation).

**Success Definition**:
- `README.md` exists at repo root; renders as well-formed Markdown (one `#` title; balanced
  fenced blocks; a valid options table; no broken inline-code).
- **Every factual claim is verifiably accurate against the shipped code** (the validation
  gates below check each): the options table defaults match `scripts/options.sh` 1:1; the
  install `run-shell` line matches `plugin.tmux`; the version floor is **3.2** (multi-line
  `status`), tested on **3.6b**; the test command is exactly `bash tests/run.sh`.
- `git diff --stat` shows ONLY `README.md` added (NO edits to PRD.md, tasks.json,
  prd_snapshot.md, .gitignore, any `scripts/*` or `tests/*`, and NO CHANGELOG — that is
  sibling task **P1.M8.T1.S2**).

## User Persona

**Target User**: (1) a new user deciding whether to install tmux-livepicker and wiring it
into their `tmux.conf`; (2) an existing user looking up an option default or the activation
flow; (3) a contributor who wants to run the test suite. The README is the only doc surface
(DOCS: this IS the docs task — Mode B).

**Use Case**: a user clones the plugin, opens `README.md`, copies an Install snippet, sets
`@livepicker-key`, reloads tmux, presses the activation key, and sees the picker. Later they
return to the Configuration table to tweak a color or the preview mode.

**User Journey**: read Overview → check Compatibility (tmux ≥ 3.2) → follow Installation
(TPM `@plugin` OR `run-shell`) → set required `@livepicker-key` → reload → Usage: prefix
→ activate → filter → navigate → confirm/cancel → (contributor) `bash tests/run.sh`.

**Pain Points Addressed**: the prior-attempt README (if any existed) failed to explain the
preview-without-switching invariant; this README states it up front (How it works) so users
trust that browsing won't corrupt their session-history timeline.

## Why

- **PRD §1 Overview**, **§2 Goals/non-goals**, **§3 User stories**, **§11 Configuration**,
  and **§14 Pollution/compatibility** are the source content (selected via PRD selectors
  `h1.0,h2.1,h2.2,h2.3,h2.11,h2.12,h2.14,h2.16`).
- **Scope cohesion.** P1.M8 is "Sync changeset-level documentation (Mode B)". S1 owns the
  README; sibling **P1.M8.T1.S2** owns the CHANGELOG / version note + the PRD §0-removal
  recommendation's home. To avoid conflict, S1 puts ONLY a short "Maintenance" pointer in
  the README (it MAY recommend §0 removal; the CHANGELOG entry itself is S2's deliverable).
- **Context is king.** A README that copies the PRD's `tmux 3.0` floor (the PRD's unverified
  guess) or omits the prefix-table activation nuance would mislead users. This PRP supplies
  the **verified** facts (architecture `system_context.md` §10: floor 3.2; §5/§8: prefix is
  None, `@livepicker-key` is a prefix-table key) so the README is correct, not aspirational.

## What

**CREATE** `README.md` at repo root. Sections (work-item §3, in this order):

1. **Overview** — PRD §1 (one paragraph: modal status-line session/window picker; live
   in-place preview; status bar grows to 2 lines; never corrupts session history/toggle).
2. **Goals / Non-goals** — PRD §2 (the Goals bullets + the Non-goals bullets, lightly
   condensed).
3. **User stories** — PRD §3 (the six `I press…` stories, condensed or verbatim).
4. **Installation** — TWO load paths, both with real precedents (see Context). State
   `@livepicker-key` is **required** (plugin.tmux prints a `display-message` and binds
   nothing if unset). Note the user's config already pre-declares
   `set -g @livepicker-key 'Space'` (a prefix-table key).
5. **Configuration** — the FULL PRD §11 options table, defaults verified 1:1 against
   `scripts/options.sh` (see Context for the exact table). All options use the `@livepicker-`
   prefix.
6. **Usage** — activate → filter → navigate → confirm/cancel, including the prefix-table
   key flow (press C-Space → prefix table → Space) and the create-on-enter behavior.
7. **How it works** — ONE paragraph: browsing links the candidate's active window into the
   current session (`link-window`) and selects it (`select-window`); it does NOT
   `switch-client`, so `client-session-changed` never fires while browsing and the
   session-history timeline + toggle are untouched. The only session switch is the single
   `switch-client` at confirm.
8. **Compatibility** — tmux **≥ 3.2** (multi-line `status`/`status-format[n]` is the binding
   feature); tested on **3.6b**. Composes with tmux-session-history, tmux-sessionx,
   tmux-resurrect, and tubular (PRD §14). Notes the prefix-table interaction with tubular.
9. **Validation** — `bash tests/run.sh` (what it does: fresh isolated socket per test via a
   PATH-wrapper shim; the user's real server is untouched; prints PASS/FAIL + summary;
   exits 0 iff all pass). List the PRD §15 clusters the suites cover.
10. **Maintenance** (short) — note that PRD.md §0 "Prior attempt" should be removed after
    human post-verification (READ-ONLY here; do not edit PRD.md). Pointer only.

### Success Criteria

- [ ] `README.md` exists at repo root with all 9 required sections (+ short Maintenance note).
- [ ] Options table has all 17 `@livepicker-*` options with defaults matching
      `scripts/options.sh` exactly (cross-check grep passes — Validation Level 3).
- [ ] Install shows BOTH the TPM `@plugin` line and the `run-shell …/plugin.tmux` line.
- [ ] Compatibility states tmux ≥ 3.2 and tested on 3.6b (NOT 3.0).
- [ ] Validation section gives the exact command `bash tests/run.sh`.
- [ ] `git diff --stat` shows ONLY `README.md` added.

## All Needed Context

### Context Completeness Check

_Pass_: a writer who has never seen this repo can produce a correct README from (a) the
ready-to-paste section skeletons in "Implementation Patterns & Key Details"; (b) the verified
facts in `research/readme_findings.md` (10 findings) and `architecture/system_context.md`;
and (c) the shipped code it must match (`scripts/options.sh`, `plugin.tmux`, `tests/run.sh`).
No guessing is required — every default, key, version, and command is pinned below.

### Documentation & References

```yaml
# MUST READ — the empirical ground-truth for THIS task (10 findings + the README skeleton).
- docfile: plan/001_fd5d622d3939/P1M8T1S1/research/readme_findings.md
  why: FINDING 1 (Mode B, runs last, reflect SHIPPED behavior; tests in flux -> describe
        clusters not a count); F2 (sibling style: session-history concise template); F3 (two
        install paths + @livepicker-key required); F4 (config defaults 1:1 with options.sh);
        F5 (floor 3.2 NOT 3.0, tested 3.6b); F6 (usage + prefix-table key flow); F7 (the one
        invariant paragraph); F8 (bash tests/run.sh); F9 (PRD §0 is a recommendation only);
        F10 (scope: ONLY README.md; CHANGELOG is S2; do not create LICENSE).
  critical: Read BEFORE writing. F4 (defaults) and F5 (version floor) are the two most
        likely accuracy errors.

# MUST READ — the architectural ground-truth (verified facts, authoritative over the PRD).
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §1 (project state: plugin NOT in TPM block; @livepicker-key Space + @livepicker-fg
        pre-declared dormant); §2 (verified env table: tmux 3.6b, prefix None, root C-M-Tab/
        C-M-BTab swap-window); §5 (prefix None, tubular C-Space in ROOT -> prefix table ->
        @livepicker-key is a PREFIX-table binding); §10 (version floor: multi-line status is
        the binding feature, "recommend documenting the floor as 3.2"; tested 3.6b).
  section: "§1", "§2", "§5", "§10".

# MUST READ — sibling scout (install precedents, option namespacing, composition).
- docfile: plan/001_fd5d622d3939/architecture/sibling_plugins_and_env.md
  why: §2 (the TWO load precedents: TPM @plugin block OR manual run-shell mirroring
        tmux-thumbs `run-shell '~/.config/tmux/plugins/tmux-thumbs/tmux-thumbs.tmux'`; the
        run-shell approach avoids a TPM install step); §10 (composition: session-history spine
        is client-session-changed which browsing never fires; sessionx different prefix key;
        resurrect safe; tubular owns status* -> livepicker composes ON TOP and restores via
        -gu). Confirms `@livepicker-*` hyphen namespacing matches session-history/sessionx.
  section: "§2", "§10".

# MUST READ — the shipped entry point (the exact bind the Install section documents).
- file: plugin.tmux
  why: the entry point. Sources scripts/options.sh for get_opt; reads @livepicker-key; if
        empty -> `tmux display-message 'tmux-livepicker: set @livepicker-key to activate'`
        and exit 0 (binds nothing); else `tmux bind-key "$KEY" run-shell
        "$CURRENT_DIR/scripts/livepicker.sh"` in the PREFIX table (default target, NO -n).
        The Install section's run-shell target is THIS file: plugin.tmux.
  gotcha: do NOT document `-n`/root binding — plugin.tmux deliberately uses the prefix table
        so it does not shadow tubular's root C-Space.

# MUST READ — the shipped defaults (the Configuration table source-of-truth).
- file: scripts/options.sh
  why: defines opt_<name>() accessors, each baking the PRD §11 default. The Configuration
        table MUST match these 1:1. Verified defaults: key=""(req), type=session, create=on,
        next-key=C-M-Tab, prev-key=C-M-BTab, nav-next-keys="Down j", nav-prev-keys="Up k",
        confirm-keys=Enter, cancel-keys=Escape, backspace-keys=BSpace, preview-mode=live,
        suppress-window-hook=on, fg=default, bg=default, highlight-fg=black,
        highlight-bg=yellow, show-count=on, status-format-index=0.
  pattern: get_opt "@livepicker-<suffix>" "<default>" — the default column is the 2nd arg.

# MUST READ — the test runner (the Validation section's exact command).
- file: tests/run.sh
  why: the entry point. Sources setup_socket.sh + helpers.sh + every tests/test_*.sh,
        discovers test_* via `compgen -A function | grep '^test_'`, runs each against a
        FRESH isolated socket (per-test setup_test/teardown_test), prints PASS/FAIL + a
        summary, exits 0 iff all passed else 1. The shim (setup_socket.sh) wraps bare `tmux`
        to a private `-L` socket so the user's real server is untouched. The Validation
        section documents `bash tests/run.sh`.
  pattern: invocation is literally `bash tests/run.sh` (run from repo root).

# MUST READ — the closest sibling README (the STYLE contract — concise: what/install/options/usage).
- file: ../tmux-session-history/README.md
  why: architecture §1 says livepicker composes most tightly with session-history; its README
        is the cleanest concise template (Title+tagline -> Why -> Features -> Install [TPM +
        manual run-shell] -> Keys -> Options -> How it works -> Requirements -> Limitations
        -> License). Mirror its tone and table formatting. DO NOT mimic sessionx's verbosity
        (Nix blocks, screenshots, long prerequisites).

# MUST READ — the PRD sections selected for this work item (the content source).
- docfile: PRD.md
  why: §1 Overview (README Overview), §2 Goals/non-goals, §3 User stories, §11 Configuration
        (the options table), §12 File layout (optional reference), §14 Pollution/compatibility
        (the Compatibility + How-it-works content), §16 risks (optional Troubleshooting).
  critical: PRD §16 says "tmux floor ... 3.0" — this is the PRD's UNVERIFIED guess. The
        README MUST state 3.2 per architecture system_context §10 (the verified binding
        feature is multi-line status). Do NOT propagate the 3.0 figure.
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md                  # READ-ONLY (FORBIDDEN to edit).
  plugin.tmux             # COMPLETE. The Install run-shell target.
  scripts/                # ALL COMPLETE (P1.M1-M6). options.sh is the defaults source.
    options.sh utils.sh state.sh filter.sh renderer.sh preview.sh
    livepicker.sh restore.sh input-handler.sh
  tests/                  # P1.M7. run.sh is the Validation command.
    setup_socket.sh helpers.sh run.sh          # COMPLETE harness.
    test_self.sh test_functional.sh test_preview.sh test_pollution.sh   # COMPLETE.
    test_restore.sh test_keyrepurpose.sh test_create.sh   # P1.M7.T6.S1 (parallel) — may not exist yet.
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M8T1S1/{PRP.md, research/readme_findings.md}   # THIS
  .gitignore
  # NOTE: README.md does NOT exist yet — THIS task creates it. No LICENSE exists (do not create one).
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  README.md   # NEW. The single user-facing doc. 9 sections + short Maintenance note.
              #   Overview (PRD §1); Goals/non-goals (§2); User stories (§3);
              #   Installation (TPM @plugin OR run-shell …/plugin.tmux; @livepicker-key required);
              #   Configuration (full §11 table, defaults 1:1 with scripts/options.sh);
              #   Usage (activate→filter→navigate→confirm/cancel; prefix-table key flow);
              #   How it works (the link-window preview invariant, one paragraph);
              #   Compatibility (tmux ≥3.2; tested 3.6b; composes w/ session-history/sessionx/
              #     resurrect/tubular);
              #   Validation (bash tests/run.sh);
              #   Maintenance (recommend removing PRD §0 after human verification — pointer only).
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (version floor): the README MUST state tmux ≥ 3.2, NOT 3.0. The PRD §16 "3.0" is an
#   unverified guess. architecture system_context §10 (authoritative) names multi-line
#   status/status-format[n] as the genuinely binding feature and recommends "documenting the
#   floor as 3.2"; tested target is the installed 3.6b. Cross-check: `tmux -V` == 3.6b.

# CRITICAL (defaults accuracy): the Configuration table MUST match scripts/options.sh 1:1.
#   The PRD §11 table and options.sh agree, but copy from options.sh (the shipped truth).
#   The 17 options + defaults are listed verbatim in "Implementation Patterns" below.
#   Note @livepicker-key default is "(required)" / empty — options.sh opt_key() returns "" and
#   plugin.tmux guards it (display-message + exit 0, binds nothing).

# CRITICAL (prefix-table activation): prefix is None (tubular sets it). tubular binds C-Space
#   in the ROOT table to switch INTO the prefix table. So @livepicker-key is a PREFIX-table
#   binding. With the user's `set -g @livepicker-key 'Space'`, the activation flow is:
#   press C-Space (root -> prefix table) -> press Space (activate). State this in Usage so a
#   user with a different prefix setup understands. plugin.tmux uses `tmux bind-key "$KEY"`
#   with NO -n (prefix table is the default target) — do NOT document a root (-n) binding.

# GOTCHA (two install paths): document BOTH. TPM: `set -g @plugin '<org>/tmux-livepicker'`
#   then `run '~/.tmux/plugins/tpm/tpm'`. Manual run-shell: `run-shell
#   '~/.config/tmux/plugins/tmux-livepicker/plugin.tmux'` (mirrors tmux-thumbs' line in the
#   user's tmux.conf). The run-shell path avoids a TPM install step. After either, set
#   @livepicker-key and reload (`prefix C-r` or `tmux source-file ~/.config/tmux/tmux.conf`).

# GOTCHA (tests in flux): P1.M7.T6.S1 (test_restore/keyrepurpose/create) is being implemented
#   IN PARALLEL. Do NOT hardcode a test COUNT or list files that may not exist yet. Describe
#   the suites by PRD §15 cluster (functional / preview / pollution / restore / key-repurpose /
#   create-on-enter) and point at `bash tests/run.sh`. The command and the runner contract are
#   stable (tests/run.sh is COMPLETE).

# GOTCHA (scope / no conflicts): produce ONLY README.md. Do NOT edit PRD.md, tasks.json,
#   prd_snapshot.md, .gitignore, any scripts/* or tests/*. Do NOT create CHANGELOG.md (sibling
#   P1.M8.T1.S2 owns it). Do NOT create LICENSE.md (out of scope; at most a one-line note
#   "add a LICENSE if you intend to distribute"). PRD §0 removal is a RECOMMENDATION in a short
#   Maintenance note — never an edit to PRD.md.

# STYLE: Markdown. Model on ../tmux-session-history/README.md (concise). Tables use the GitHub
#   pipe style. Fenced blocks are ```tmux / ```sh / ```bash as appropriate. One `#` H1 title.
#   Keep the document scannable — prefer tables and short paragraphs over prose walls.
```

## Implementation Blueprint

### Data models and structure

No data model. The "model" is the **README section map** + the **verified facts** each
section consumes:

```markdown
# tmux-livepicker                      <- H1 title + one-line tagline (PRD §1)
## Overview                            <- PRD §1 (1 paragraph)
## Goals                               <- PRD §2 Goals bullets (condensed)
## Non-goals                           <- PRD §2 Non-goals bullets
## User stories                        <- PRD §3 (the six "I press…" stories)
## Installation                        <- 2 paths (TPM @plugin / run-shell) + @livepicker-key required
## Configuration                       <- the full §11 options table (defaults 1:1 w/ options.sh)
## Usage                               <- activate→filter→navigate→confirm/cancel + prefix flow
## How it works                        <- the link-window preview invariant (1 paragraph)
## Compatibility                       <- tmux ≥3.2; tested 3.6b; composes w/ the 4 siblings
## Validation                          <- bash tests/run.sh
## Maintenance                         <- recommend PRD §0 removal after verification (pointer)
```

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE README.md — title + Overview + Goals/Non-goals + User stories (PRD §1/§2/§3)
  - CREATE: README.md (NEW; repo root).
  - TITLE: `# tmux-livepicker` + a one-line tagline (e.g. "A modal status-line session and
        window picker that previews candidates live, in place, without leaving your session.").
  - OVERVIEW: one paragraph from PRD §1 (status bar grows to 2 lines; line 1 = picker; area
        below = live preview of all panes of the highlighted session; filter by typing; move
        with your own window-nav keys; confirm lands / cancel restores exactly; never corrupts
        session history or the toggle).
  - GOALS: PRD §2 Goals bullets, condensed (status-line picker; live in-place all-panes
        preview; filter + repurposed nav keys; create-on-enter; zero history/toggle pollution;
        exact restore).
  - NON-GOALS: PRD §2 Non-goals bullets (no popup UI; one window at a time; no pane picking;
        no MRU; single-client).
  - USER STORIES: PRD §3 six stories (activate; next-window key moves sessions; type `log`
        filters; Enter lands; type `newproj` + Enter creates; Escape restores).
  - FOLLOW style: ../tmux-session-history/README.md (concise; short paragraphs).

Task 2: APPEND Installation section (two load paths + required key)
  - INSTALL (option A — TPM):
        ```tmux
        set -g @plugin '<org>/tmux-livepicker'
        ```
        then `run '~/.tmux/plugins/tpm/tpm'` and `prefix + I`.
  - INSTALL (option B — manual run-shell; mirrors tmux-thumbs):
        ```sh
        git clone <repo> ~/.config/tmux/plugins/tmux-livepicker
        ```
        ```tmux
        run-shell '~/.config/tmux/plugins/tmux-livepicker/plugin.tmux'
        ```
  - REQUIRED KEY: state `@livepicker-key` is required — if unset, the plugin prints a
        `display-message` and binds nothing. Example:
        ```tmux
        set -g @livepicker-key 'Space'
        ```
        Note the user's config already pre-declares this. Reload after setting
        (`tmux source-file ~/.config/tmux/tmux.conf`).
  - ACCURACY: the run-shell target is `plugin.tmux` (the shipped entry point — verified in
        plugin.tmux: `tmux bind-key "$KEY" run-shell "$CURRENT_DIR/scripts/livepicker.sh"`).

Task 3: APPEND Configuration section (full §11 table, defaults 1:1 with scripts/options.sh)
  - TABLE: all 17 `@livepicker-*` options with Default + Purpose columns (see "Implementation
        Patterns" for the verbatim table). Copy defaults from scripts/options.sh (the shipped
        truth), NOT from memory.
  - NAMING: every option uses the `@livepicker-` prefix. State this above the table.
  - CROSS-CHECK (Validation Level 3 will assert): each default equals the 2nd arg of the
        matching `get_opt "@livepicker-<suffix>" "<default>"` in options.sh.

Task 4: APPEND Usage section (activate→filter→navigate→confirm/cancel + prefix flow)
  - ACTIVATE: press your prefix (C-Space with tubular) to enter the prefix table, then press
        `@livepicker-key` (Space by default). The status bar grows to two lines; line 1 is the
        picker; the area below shows the highlighted session's panes live.
  - FILTER: type to filter (substring, case-insensitive); Backspace removes a char.
  - NAVIGATE: `C-M-Tab`/`C-M-BTab` (your window-nav keys, repurposed) or `Down`/`j`,
        `Up`/`k` move the selection; the preview follows live.
  - CONFIRM: `Enter` lands on the selection. In session mode with no match and
        `@livepicker-create on`, it creates a session from your query and switches to it.
  - CANCEL: `Escape` clears the query if non-empty, else cancels and restores everything
        exactly (status, keys, focus).
  - NOTE: while active, unmatched keys do not reach the previewed panes (the `livepicker` key
        table is fully modal).

Task 5: APPEND How it works section (the one invariant — one paragraph)
  - CONTENT: browsing does NOT switch your session. The plugin links the highlighted
        session's active window into your current session with `tmux link-window` and selects
        it with `select-window` so all its panes render live. `select-window` fires
        `session-window-changed` (suppressed by default via `@livepicker-suppress-window-hook`)
        but NOT `client-session-changed`, so the tmux-session-history timeline and the toggle
        pointer are untouched while you browse. The only session switch in the whole flow is
        the single `switch-client` at confirm. Cancelling leaves zero trace.
  - LENGTH: one paragraph (3–5 sentences). This is the trust-building sentence.

Task 6: APPEND Compatibility section (version floor + sibling composition)
  - VERSION: requires tmux **≥ 3.2** (multi-line `status`/`status-format[n]` is the binding
        feature). Tested on **3.6b**. Do NOT say 3.0.
  - COMPOSES WITH: tmux-session-history (the timeline it protects), tmux-sessionx,
        tmux-resurrect, and tubular — it mutates only well-scoped global options and restores
        them on exit (PRD §14).
  - NOTE: with tubular, prefix is `None` and `C-Space` enters the prefix table, so
        `@livepicker-key` is a prefix-table binding.

Task 7: APPEND Validation section (bash tests/run.sh) + short Maintenance note
  - VALIDATION: run `bash tests/run.sh` from the repo root. It spins up a private, isolated
        tmux socket per test (a `tmux` PATH-wrapper shim), so your real running server is never
        touched. It prints PASS/FAIL per test and a summary, and exits 0 iff all passed.
        Suites cover the PRD §15 clusters: activation/filtering/navigation/confirm/cancel
        (functional), the live all-panes preview, the zero-pollution invariant, byte-exact
        restore, the key-repurpose revert, and create-on-enter.
  - MAINTENANCE: a one-paragraph note that PRD.md §0 "Prior attempt" is a build-time scaffold
        to be removed by a human after post-verification (the README does not edit PRD.md).
        Optionally point to the CHANGELOG (sibling task P1.M8.T1.S2).

Task 8: VALIDATE (Level 1 markdown + Level 3 accuracy cross-checks + Level 4 tests still green)
  - RUN: a markdown lint/render check (e.g. `markdownlint README.md` if available, else a
        manual render); the Level 3 accuracy greps (defaults match options.sh; run-shell target
        is plugin.tmux; floor is 3.2; test cmd is bash tests/run.sh); confirm `bash tests/run.sh`
        is unaffected by the doc change (it should still pass — README adds no code).
  - ASSERT: `git diff --stat` shows ONLY README.md added.
```

### Implementation Patterns & Key Details

#### The verbatim Configuration table (defaults from `scripts/options.sh`)

> Copy this table. Defaults are verified 1:1 against `scripts/options.sh` `opt_<name>()`
> accessors (the shipped truth). The `@livepicker-` prefix applies to all.

| Option                             | Default    | Purpose                                                                                                  |
| ---------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------- |
| `@livepicker-key`                  | (required) | Prefix-table key that activates the picker. If unset, the plugin prints a `display-message` and binds nothing. |
| `@livepicker-type`                 | `session`  | `session` or `window`. What the picker lists.                                                            |
| `@livepicker-create`               | `on`       | In session mode, create a new session from the query on Enter when nothing matches.                      |
| `@livepicker-next-key`             | `C-M-Tab`  | Key that moves to the next session. Defaults to this user's next-window key.                             |
| `@livepicker-prev-key`             | `C-M-BTab` | Key that moves to the previous session. Defaults to this user's prev-window key.                         |
| `@livepicker-nav-next-keys`        | `Down j`   | Extra next-session keys.                                                                                 |
| `@livepicker-nav-prev-keys`        | `Up k`     | Extra previous-session keys.                                                                             |
| `@livepicker-confirm-keys`         | `Enter`    | Confirm and land on the selection.                                                                       |
| `@livepicker-cancel-keys`          | `Escape`   | Clear the query, or cancel if the query is empty.                                                        |
| `@livepicker-backspace-keys`       | `BSpace`   | Remove the last filter character.                                                                        |
| `@livepicker-preview-mode`         | `live`     | `live` (link-window, all panes), `snapshot` (capture-pane, active pane), or `off`.                       |
| `@livepicker-suppress-window-hook` | `on`       | Clear `session-window-changed` during the picker to avoid focus-resync side effects.                     |
| `@livepicker-fg`                   | `default`  | Picker text color.                                                                                       |
| `@livepicker-bg`                   | `default`  | Picker background.                                                                                       |
| `@livepicker-highlight-fg`         | `black`    | Highlighted (current) item text.                                                                         |
| `@livepicker-highlight-bg`         | `yellow`   | Highlighted item background.                                                                             |
| `@livepicker-show-count`           | `on`       | Show `index/total` in the picker.                                                                        |
| `@livepicker-status-format-index`  | `0`        | Which status line the picker takes.                                                                      |

#### Install section skeleton (two paths)

```markdown
## Installation

**Option A — Tmux Plugin Manager (TPM):**

```tmux
set -g @plugin '<your-org>/tmux-livepicker'
```
Then run TPM's install (`prefix + I`).

**Option B — manual `run-shell` (no TPM step):**

```sh
git clone <repo-url> ~/.config/tmux/plugins/tmux-livepicker
```

```tmux
run-shell '~/.config/tmux/plugins/tmux-livepicker/plugin.tmux'
```

> `@livepicker-key` is **required**. If it is unset, the plugin prints a message and binds
> nothing. Set it (and reload) before first use:

```tmux
set -g @livepicker-key 'Space'
```

Reload tmux (`tmux source-file ~/.config/tmux/tmux.conf`) and press your prefix, then the key.
```

#### Usage section skeleton (prefix-table flow)

```markdown
## Usage

1. **Activate** — press your prefix, then `@livepicker-key` (`Space` by default). With
   tubular the prefix is `None` and `C-Space` enters the prefix table, so the sequence is
   `C-Space` → `Space`. The status bar grows to two lines: line 1 is the picker; the area
   below shows the highlighted session's panes, live.
2. **Filter** — type to filter the list (substring, case-insensitive); `BSpace` removes a char.
3. **Navigate** — `C-M-Tab` / `C-M-BTab` (your window-nav keys, repurposed) or `Down` / `j`
   and `Up` / `k` move the selection. The preview follows live.
4. **Confirm** — `Enter` lands on the selection. In `session` mode with no match and
   `@livepicker-create on`, it creates a session from your query and switches to it.
5. **Cancel** — `Escape` clears the query if non-empty, otherwise cancels and restores your
   status line, key table, and focus exactly.

While the picker is active, unmatched keys do not reach the previewed panes.
```

### Integration Points

```yaml
FILES (touched):
  - create: "README.md"   # repo root. The ONLY file this task produces.

FILES (read-only references, do NOT edit):
  - scripts/options.sh    # the defaults source for the Configuration table.
  - plugin.tmux           # the Install run-shell target + the @livepicker-key guard.
  - tests/run.sh          # the Validation command.
  - PRD.md                # READ-ONLY content source (§1/§2/§3/§11/§14). Never edit.
  - ../tmux-session-history/README.md   # the STYLE template.

NO CODE CHANGES:
  - The README adds no code. `bash tests/run.sh` is unaffected and must still pass.
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Markdown well-formedness (pick one available; else eyeball a render).
markdownlint README.md 2>/dev/null || true        # if markdownlint is installed
# OR render-check: open in a Markdown previewer / `glow README.md` if available.

# Structural sanity (no tool needed):
grep -c '^## ' README.md          # expect >= 9 required sections + Maintenance
grep -n '^# tmux-livepicker' README.md   # exactly one H1 title
# Expected: one H1; balanced fenced blocks; a pipe-table under ## Configuration.
```

### Level 2: Render / Link Check (Component Validation)

```bash
# Every fenced block is a complete, copy-pasteable snippet; every inline-code is closed.
# Verify the three fenced blocks: TPM @plugin, run-shell line, @livepicker-key set.
grep -n "set -g @plugin" README.md            # Option A present
grep -n "run-shell .*plugin.tmux'" README.md  # Option B present (target == plugin.tmux)
grep -n "@livepicker-key" README.md           # required-key callout present
# Expected: all three present. No empty fenced blocks.
```

### Level 3: Accuracy Cross-Checks (the core gate — every claim matches shipped code)

```bash
# (a) The Configuration defaults MUST match scripts/options.sh 1:1.
#     For each option, the README default == the 2nd arg of get_opt in options.sh.
#     Spot-check a few (and visually diff the whole table against options.sh):
grep -o 'get_opt "@livepicker-type" "[^"]*"' scripts/options.sh        # -> session
grep -o 'get_opt "@livepicker-preview-mode" "[^"]*"' scripts/options.sh # -> live
grep -o 'get_opt "@livepicker-highlight-bg" "[^"]*"' scripts/options.sh # -> yellow
# README must show the same values.

# (b) The Install run-shell target is the shipped entry point.
grep -q 'run-shell "$CURRENT_DIR/scripts/livepicker.sh"' plugin.tmux \
  && echo "plugin.tmux is the entry point (matches README)" \
  || echo "MISMATCH: re-check the Install target"

# (c) Version floor is 3.2 (NOT 3.0); tested target documented.
grep -E 'tmux .*3\.2' README.md && echo "floor 3.2 present"
! grep -E 'tmux .*3\.0( |$)' README.md && echo "no stale 3.0 floor" || echo "WARNING: 3.0 present"

# (d) The test command is exactly bash tests/run.sh.
grep -F 'bash tests/run.sh' README.md && echo "validation command present"

# (e) No forbidden edits.
git diff --stat -- README.md            # ONLY README.md should appear
git diff --name-only | grep -vE '^README.md$' && echo "WARNING: unexpected files touched" || echo "clean"
# Expected: README.md only.
```

### Level 4: Documentation / Regression Validation

```bash
# The README adds NO code, so the test suite must be unaffected and still green.
bash tests/run.sh
# Expected: same PASS/FAIL outcome as before this task (exits 0 iff all pass). The README
# must not change any script or test. If run.sh now fails, a script/test was accidentally
# edited — revert it (FORBIDDEN).

# Confirm scope boundaries (FORBIDDEN files untouched).
git diff --name-only | grep -E 'PRD.md|tasks.json|prd_snapshot.md|.gitignore|^scripts/|^tests/' \
  && echo "ERROR: forbidden file edited" || echo "scope clean"
# Expected: scope clean (no matches).

# Confirm no CHANGELOG/LICENSE was created (owned by S2 / out of scope).
ls CHANGELOG* LICENSE* 2>/dev/null && echo "WARNING: created an out-of-scope file" || echo "no extra files"
# Expected: no extra files.
```

## Final Validation Checklist

### Technical Validation

- [ ] All 4 validation levels completed successfully.
- [ ] Level 1: README renders as well-formed Markdown (one H1; balanced fences; valid table).
- [ ] Level 3 (a): Configuration table defaults match `scripts/options.sh` 1:1.
- [ ] Level 3 (b): Install run-shell target is `plugin.tmux` (matches the shipped entry point).
- [ ] Level 3 (c): Compatibility states tmux **≥ 3.2**, tested **3.6b** (no stale 3.0).
- [ ] Level 3 (d): Validation section gives the exact command `bash tests/run.sh`.
- [ ] Level 3 (e): `git diff --stat` shows ONLY `README.md` added.
- [ ] Level 4: `bash tests/run.sh` unaffected (README adds no code).

### Feature Validation

- [ ] All 9 required sections present (Overview, Goals/non-goals, User stories, Installation,
      Configuration, Usage, How it works, Compatibility, Validation) + short Maintenance note.
- [ ] Installation documents BOTH load paths (TPM `@plugin` and manual `run-shell`).
- [ ] Installation states `@livepicker-key` is required.
- [ ] Usage covers activate → filter → navigate → confirm/cancel, incl. the prefix-table flow.
- [ ] How it works states the link-window preview invariant in one paragraph.
- [ ] Compatibility lists composition with session-history, sessionx, resurrect, tubular.

### Code Quality Validation

- [ ] Follows the concise sibling style of `tmux-session-history/README.md`.
- [ ] No generic references — all defaults/keys/commands are specific and verified.
- [ ] Tables use consistent GitHub pipe style.
- [ ] Anti-patterns avoided (see below).

### Documentation & Deployment

- [ ] Copy-pasteable fenced blocks (Install snippets actually work).
- [ ] The prefix-table activation nuance is explained (users with other prefix setups).
- [ ] No claim contradicts the shipped code or the architecture ground-truth.

---

## Anti-Patterns to Avoid

- ❌ Don't state tmux 3.0 as the floor — the verified binding feature is multi-line `status`
  (≥ 3.2); 3.6b is the tested target. The PRD's "3.0" is an unverified guess.
- ❌ Don't copy the options table from memory — copy defaults from `scripts/options.sh`.
- ❌ Don't document a root (`-n`) activation binding — `plugin.tmux` uses the prefix table so
  it does not shadow tubular's root `C-Space`.
- ❌ Don't hardcode a test count or list test files that may not exist yet (T6 is in flux) —
  describe the suites by PRD §15 cluster and point at `bash tests/run.sh`.
- ❌ Don't edit PRD.md, tasks.json, prd_snapshot.md, .gitignore, any `scripts/*` or `tests/*`.
- ❌ Don't create CHANGELOG.md (sibling P1.M8.T1.S2 owns it) or LICENSE (out of scope).
- ❌ Don't pad the README with Nix blocks/screenshots/long prerequisite lists (that is
  sessionx's style; mirror session-history's concision instead).
- ❌ Don't turn "How it works" into an architecture essay — one paragraph, the invariant only.
