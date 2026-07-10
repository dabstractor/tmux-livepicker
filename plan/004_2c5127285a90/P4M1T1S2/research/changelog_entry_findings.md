# P4.M1.T1.S2 research: CHANGELOG entry for the plan-004 changeset

Synthesis of the facts the implementer needs. Read this FIRST; it is the TL;DR.

## 0. THE LOAD-BEARING FINDING: CHANGELOG.md does NOT exist on this branch

- The task runs in the `main` worktree
  (`/home/dustin/.config/tmux/plugins/tmux-livepicker`, branch `main` @ fe07a02).
- `CHANGELOG.md` is ABSENT: not in the working tree, NOT in HEAD
  (`git cat-file -e HEAD:CHANGELOG.md` -> "does not exist"), and NO commit
  reachable from `main` ever added it (`git log -- CHANGELOG.md` is empty).
- The "changelog" commits reachable from main are misleading:
  - `0743a53 "Tighten changelog format and document config caveats"` touched
    `README.md` + `tests/setup_socket.sh`, NOT CHANGELOG.md.
  - `f722bea "Add changelog entry for plan-003 features and sweep em dashes"`
    touched `plan/003_*/P4M1T1S2/PRP.md` + research + tasks.json, NOT
    CHANGELOG.md (it is the planning commit, not the implementation).
- CHANGELOG.md only ever existed on the SIBLING branch `prd-updates` (checked
  out in the other worktree `tmux-livepicker-prd-updates` @ 5d85cd5), added by
  `2af5a44` and modified by `75a0b1b`/`e581b24`/`18aebc0`.
- => This task must CREATE CHANGELOG.md fresh on `main`. The task contract
  explicitly says: "Check if CHANGELOG.md exists. If not, create it."

## 1. DECISION: create fresh = intro + ONE new plan-004 [Unreleased] block

- Create CHANGELOG.md with: the standard intro (`# Changelog` + the Keep a
  Changelog reference line) + exactly ONE new `## [Unreleased]: <subtitle>`
  block for the plan-004 changeset.
- Do NOT port the prd-updates history (rev-001 initial impl, rev-002 theme
  tabs/defer). Reasons: (a) the task scope is the plan-004 changeset
  ("Add an [Unreleased] entry"); (b) the prd-updates CHANGELOG carries 19 em
  dashes (never swept there), so porting it would import a file-wide em-dash
  problem and expand scope; (c) the plan-003 entry does not exist in ANY
  committed CHANGELOG to restore; (d) main and prd-updates are divergent
  branches. Creating fresh with the one in-scope entry is the deterministic,
  lowest-risk, task-faithful action.
- IMPORTANT consequence: because the file is created fresh, there is NOTHING to
  em-dash-sweep. The implementer only needs to keep the NEW prose em-dash-free.
  (Contrast the plan-003 PRP, which had to sweep ~19 existing lines.)

## 2. Format template (mirror the prd-updates "theme-matched tabs" block)

Recovered via `git show prd-updates:CHANGELOG.md` (163 lines). The format:
- Intro (lines 1-4): `# Changelog` heading + an intro paragraph referencing
  [Keep a Changelog](https://keepachangelog.com/). Reproduce this verbatim.
- Newest-first: each changeset is its own `## [Unreleased]: <subtitle>` block
  (COLON separator; the repo uses `[Unreleased]` because no versioned tag
  exists). The newest block sits at the top, directly under the intro.
- Section sub-headers used: `### Added`, `### Fixed`, `### Documented
  corrections`, `### Notes for maintainers`. A pure-feature changeset uses
  `### Added`.
- STRUCTURAL TEMPLATE = the prd-updates `## [Unreleased]: theme-matched tabs
  and deferred preview` -> `### Added` block. Its shape:
  - One bullet per feature/option, each starting with a **bold name**, the
    default, a PRD section ref, then what it does + the user-visible effect.
  - Then a bullet asserting the invariants are unchanged.
  - Then a bullet naming the escape hatches that remain.
- Tone: evidence-first, dense, active voice. Every option/key/command literal in
  `code` spans. Match this density.

## 3. The three feature bullets (PRD §8 / §6.6+§7 / §23+§4)

1. **Two-axis discovered navigation** (PRD §8; plan P1). The picker now has two
   navigation axes, and BOTH reuse the keys the user already has for that axis,
   discovered from their live key tables. WINDOW axis (flip the highlighted
   session's windows in the preview): defaults to the user's `next-window` /
   `previous-window` / `select-window -n`/`-p` bindings (incl. the
   `swap-window ... ; select-window` compounds). SESSION axis (move the
   highlight between candidates): defaults to the user's `switch-client -n` /
   `-p` bindings plus the arrow keys (`Down`/`Up`). Discovery reads
   `tmux list-keys -T root` and `-T prefix`, drops plain letters/digits
   (reserved for the query), de-duplicates, and excludes the fixed control keys.
   The four options `@livepicker-session-next-keys` / `-prev-keys` /
   `@livepicker-window-next-keys` / `-prev-keys` override discovery when set.
   This REPLACES the old single-axis "repurposed window-nav into session-nav"
   model (PRD §8 explicitly dropped it). Low-cost revert: a modal key table
   switches back on cancel.
2. **Window-flip preview + confirm-on-window** (PRD §6.6, §7, §2; plan P2).
   Flipping steps through a candidate's windows live in the preview, with the
   live preview following each flip. Confirm lands on the EXACT window being
   previewed: it resolves the target session from the ranked list and the target
   window from the window cursor, commits that window with one `select-window`,
   then `switch-client`s (the client arrives on the chosen session AND window).
   Flipping never changes the candidate's OWN active window (leave-no-trace,
   Invariant B): flips link the chosen window into the driver and select it
   there; no command targets the candidate session.
3. **Pane immutability (Invariant C)** (PRD §23, §4; plan P3). No pane of any
   session (candidate, driver, or bystander) is moved, resized, reordered,
   reset, or altered by browsing, confirming, or cancelling, even though the
   preview is a shared window object. Enforced by prevention, not repair: the
   driver is pinned (`window-size manual` + height pin) so the status grow and
   the shared preview window cannot reflow; detached candidates are pinned at
   link time and restored on leave; and a pane-geometry snapshot taken at
   activate drives a drift-gated restore on exit (restore acts only if geometry
   drifted). Client-bearing candidates cannot be pinned (manual reverts their
   client view), so for STRICT immutability across every session use
   `@livepicker-preview-mode snapshot` (capture-pane, never links/resizes).

## 4. Defaults to state (verified in scripts/options.sh + §11)

- The four nav options default to DISCOVERED (`opt_session/window_next/prev_keys`
  return "" => discover; options.sh lines 30-33). State this as "axes
  discovered" / "defaults to your own keys".
- `@livepicker-preview-fit` default `clip`.
- `@livepicker-preview-defer` default `on`.
- (The task explicitly lists these three default groups.)

## 5. Invariants that MUST be stated as unchanged (PRD §4 A/B/C, §14)

The entry asserts NONE of the three changeset features changes the
pollution/restore invariants:
- **A (no client switch while browsing):** browsing never calls `switch-client`;
  the only switch is the single one at confirm. `client-session-changed` does
  not fire while browsing, so the tmux-session-history timeline and the
  `@session-history-prev` toggle are untouched.
- **B (no candidate state mutation while browsing):** flipping a candidate's
  windows links the chosen window into the driver and selects it there; no
  command targets the candidate, so its active window and `window_layout` are
  byte-identical before/after. Moving on or cancelling leaves every candidate
  exactly as it was (leave-no-trace).
- **C (pane immutability):** no pane of any session is moved or resized (see
  feature 3). Cancel restores the driver's window and pane geometry (drift-gated).

## 6. Escape hatch that REMAINS

- `@livepicker-preview-mode snapshot` is the strict-immutability escape hatch:
  it previews with `capture-pane` and never links (or resizes) a candidate
  window, so no candidate's geometry can ever drift. (The task explicitly names
  this.)

## 7. write-tech-docs lint gate — CORRECT PATH + rules

- The sibling P4.M1.T1.S1 PRP says the skill/lint is "NOT on disk in this
  environment". That conclusion is based on `~/.pi/agent/skills/` being empty of
  it. The script DOES exist (verified) at:
  `/home/dustin/projects/writing-skills/skills/write-tech-docs/scripts/lint.sh`
  Run `bash <that path> CHANGELOG.md`; require exit 0 (`lint: 0 hit(s)`).
- Rules (it strips fenced + inline code first, then fails on):
  1. Em dashes (U+2014) or ` -- ` — banned outright.
  2. Tell-words (case-insensitive whole word): powerful, robust, elegant,
     seamless/seamlessly, comprehensive, cutting-edge, state-of-the-art,
     revolutionary, game-changing, next-generation, blazing-fast, lightning-fast,
     intuitive, effortless, frictionless, ultimate, stunning, beautiful,
     incredible, leverage, utilize, unlock, empower, supercharge, revolutionize,
     streamline, elevate, delve, tapestry, realm, landscape, moreover,
     furthermore, truly, incredibly.
  3. A prose paragraph over 100 words (skips headings/lists/tables/quotes).
- Because the file is CREATED FRESH, the em-dash rule is satisfied by keeping
  the new prose clean (there is no existing content to sweep). Still run lint.sh
  (or the grep fallback) as the gate.
- Fallback grep (rules 1+2): `grep -nP '\x{2014}| -- ' CHANGELOG.md` empty;
  `grep -niEw '<tell-word list>' CHANGELOG.md` empty.

## 8. Verified code facts (for accuracy; READ-ONLY, do not edit)

- scripts/options.sh lines 30-33: the 4 two-axis accessors
  (opt_session_next_keys / opt_session_prev_keys / opt_window_next_keys /
  opt_window_prev_keys), all default "" (empty = discover). The OLD
  opt_next_key/opt_prev_key/opt_nav_* are GONE.
- scripts/state.sh: window-cursor keys STATE_CAND_WIN_SESSION / _LIST / _CURSOR
  + STATE_PREVIEW_WIN_ID (P2); candidate-pin STATE_CAND_PIN_SESSION /
  STATE_CAND_PIN_WS (P3); pane-geometry ORIG_PANE_GEOMETRY (P3, drift-gated
  restore). All members of _STATE_RUNTIME_KEYS or auto-cleared by the
  `@livepicker-orig-` grep (so clear_all_state tears them down).
- scripts/input-handler.sh: actions include next-window / prev-window (the flip)
  alongside next-session / prev-session / confirm / cancel / type / backspace.
- tests/: 16 test files, 96 test funcs total (incl. tests/test_window_flip.sh;
  tests/test_pane_immutability.sh is being added by the parallel P3.M3.T1.S1).
  Citing a count is OPTIONAL (the rev-002 Added block did not cite one).

## 9. Parallel-execution context (no conflict)

- P4.M1.T1.S1 (README sync) is implemented in parallel and does NOT touch
  CHANGELOG.md (it owns README only). No file conflict.
- P3.M3.T1.S1 adds tests/test_pane_immutability.sh only (a test file); no
  CHANGELOG overlap.
- The CHANGELOG entry must be SELF-CONTAINED per the task contract (3 features +
  defaults + invariants A/B/C + snapshot escape hatch); do not hard-depend on
  the README's in-flight state.
