# CHANGELOG.md findings — P1.M8.T1.S2

Source: live read of repo + `plan/001_fd5d622d3939/architecture/system_context.md`
(§3 the three invariants, §10 the floor) + the PRD (§0, §15, §16) + sibling
CHANGELOGs. All facts verified on 2026-07-06.

## FINDING 1 — This is the Mode B docs companion to the README (S1); non-conflicting
`<item_description>` §1 / §4 (OUTPUT): create **CHANGELOG.md** (or a README maintainers
section). Sibling task **P1.M8.T1.S1** owns the **README.md**; its PRP explicitly defers
the CHANGELOG to S2 ("Do NOT create CHANGELOG.md (sibling P1.M8.T1.S2 owns it)") and adds
only a short "Maintenance" note that POINTS to this CHANGELOG. => S2 produces
**CHANGELOG.md** at repo root — the canonical home of the PRD §0-removal recommendation.
S1 and S2 touch DIFFERENT files (README.md vs CHANGELOG.md); no conflict.

## FINDING 2 — CHANGELOG style contract (only one sibling has one)
Of session-history, sessionx, resurrect, thumbs, tubular, ONLY **tmux-resurrect** has a
CHANGELOG (`../tmux-resurrect/CHANGELOG.md`). Its style:
  `# Changelog` H1 → `### master` (unreleased) with concise bullets → `### vX.Y.Z, date`
  release sections, newest first. Bullets are one line, present-tense, feature/bugfix
  scoped. No categories under version headers in resurrect, BUT keepachangelog.com
  (Added/Changed/Notes) is the widely-accepted convention and reads better for a
  documented-correction entry. Use keepachangelog categories for THIS file (clearer for
  the "floor correction" + "invariants" + "maintainer action" content); keep the resurrect
  concision (short bullets, one H1, newest-first).

## FINDING 3 — No git tag exists; this is the INITIAL implementation (unreleased)
`git tag` → (none). `git log` → 30 commits; first = "docs: add product requirements
document"; last = "Add restore, key-repurpose, and create-on-enter tests". The whole
plugin (P1.M1–M6) + test suite (P1.M7) is COMMITTED; P1.M8 is the docs milestone
(S1=README, S2=CHANGELOG). => The single CHANGELOG entry documents the **initial
implementation**, under an `## [Unreleased]` header (keepachangelog convention for
in-development, no released tag yet). Do NOT invent a semver tag the repo does not have.

## FINDING 4 — The three PROVEN invariants (architecture system_context §3, verbatim)
The work-item §3 names them ("no client-session-changed while browsing; modal key-table;
multi-line status composition"). They are architecture §3 A/B/C, PROVEN during research:
  A. **Browsing never fires `client-session-changed`.** `select-window` fires
     `session-window-changed` but NOT `client-session-changed`; `link-window`/`unlink-window`
     fire neither. Browsing via link+select therefore leaves the tmux-session-history
     timeline + `@session-history-prev` toggle untouched; the only `client-session-changed`
     is the single confirm-time `switch-client`. (Upholds PRD §4 / §14.)
  B. **A non-root `key-table` is fully modal (drops unmatched keys).** While `key-table` is
     `livepicker`, tmux consults ONLY that table; an unbound key is DROPPED, never passed to
     root/prefix or the pane. The preview is genuinely display-only. (This makes the PRD §8
     "copy prefix+root bindings into livepicker" step necessary, not optional.)
  C. **Multi-line status composes correctly.** With `status=2`, `status-format[0]=#(renderer.sh)`
     (picker) and `status-format[1]` UNSET, line 1 = picker and line 2 = tmux's built-in
     default composite (status-left + window-status-format + status-right) = the user's
     tubular window-status line, live-composed. (Upholds PRD §10.)

## FINDING 5 — The floor correction: 3.2 (NOT 3.0)
PRD §16 (the PRD's UNVERIFIED guess) says: "tmux floor ... 3.0 ... Target 3.0 as the floor;
test on the installed 3.6b." architecture system_context §10 (AUTHORITATIVE, verified):
"The genuinely binding feature is multi-line status/status-format[n], likely introduced in
3.2 ... Recommend documenting the floor as **3.2** ... On the target machine this is moot
(3.6b)." `tmux -V` == 3.6b. => The CHANGELOG documents the CORRECTION: floor is **3.2**
(multi-line `status` is the binding feature), corrected up from the PRD's 3.0; tested on
3.6b. The README (S1) states 3.2 too — the CHANGELOG entry records WHY (the verified
binding feature + the correction).

## FINDING 6 — PRD §0 removal is a HUMAN action (SOW forbids editing PRD.md)
PRD §0 last paragraph: "After the implementation lands and is verified, remove this entire
section on the next edit." The SOW FORBIDDEN OPERATIONS list forbids any automated agent
from editing `PRD.md` (READ-ONLY). `<item_description>` §1 resolution: "do NOT edit PRD.md;
instead record the recommendation in a CHANGELOG.md entry and surface it in the README's
validation section ('After verification, a human should remove PRD §0')." => The CHANGELOG
entry records the recommendation (under a "Notes for maintainers" section). The verification
trigger is "the PRD §15 validation suite passes on the REAL environment" — i.e. beyond the
isolated `bash tests/run.sh` socket harness, a human confirms §15 on the live machine. State
that trigger precisely.

## FINDING 7 — Validation reference: `bash tests/run.sh` + PRD §15 clusters
The §15 validation suite is run via `bash tests/run.sh` (tests/run.sh is COMPLETE — sources
setup_socket.sh + helpers.sh + every tests/test_*.sh; discovers test_*; fresh isolated
socket per test; exits 0 iff all pass). Test files present (all COMPLETE): test_self.sh,
test_functional.sh (§15.17), test_preview.sh (§15.19), test_pollution.sh (§15.18),
test_restore.sh (§15.21), test_keyrepurpose.sh (§15.20), test_create.sh (§15.22). The
CHANGELOG entry references `bash tests/run.sh` and the §15 clusters as the gating evidence.
Do NOT hardcode a test count (stable now, but the entry should reference the command).

## FINDING 8 — Scope boundary (no conflicts, no forbidden edits)
ONLY file produced: `CHANGELOG.md` at repo root. Do NOT touch PRD.md, tasks.json,
prd_snapshot.md, .gitignore, any scripts/* or tests/* (all COMPLETE/IMMUTABLE), and do NOT
create README.md (sibling S1 owns it) or LICENSE (out of scope). The CHANGELOG adds NO
code, so `bash tests/run.sh` is unaffected and must still pass. `git diff --stat` must show
ONLY `CHANGELOG.md` added (plus whatever S1 adds in parallel for README.md — that is
expected and non-overlapping).
