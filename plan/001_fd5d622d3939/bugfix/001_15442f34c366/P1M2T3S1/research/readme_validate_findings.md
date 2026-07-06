# Research — P1.M2.T3.S1: Remove non-existent `./validate.sh` reference from README

> Documentation-only fix for bugfix **Issue 5 (Minor)**.
> Source of truth: `plan/001_fd5d622d3939/bugfix/001_15442f34c366/architecture/bugfix_findings.md` §ISSUE 5.

## FINDING 1 — `validate.sh` does not exist anywhere in the repo

```text
$ find . -name 'validate.sh' -not -path '*/.git/*'
(empty)
```

Only test runner present is `tests/run.sh`. Confirmed at the repo root listing:
no `validate.sh`, no `Makefile` target wrapping it. (Also checked: no
`package.json`/other build manifest references it.)

## FINDING 2 — The exact broken text (README.md, the `## Validation` section)

The `## Validation` heading starts at README.md **line 172**. The broken clause
spans the wrapped paragraph **lines 180–183**. Byte-level view (`cat -A`, ASCII
shown; line 180 carries the `2–3` en-dash):

```
179: passed. Expect the full suite to take roughly **2–3 minutes** (each test starts
180: a fresh isolated tmux server and sources the user config); a `VALIDATE_SKIP_SLOW=1`
181: budget is available in `./validate.sh` for faster static + E2E checks. The suites cover the PRD §15 clusters:
```

(Note: `grep -n` numbers these as 181/182 because line 1 is offset by the
code-fence; the on-screen `sed` shows the paragraph at lines 180–181. Either way
the anchor text is unique and unambiguous — see FINDING 4.)

The broken clause to remove is the trailing sub-clause:
`a \`VALIDATE_SKIP_SLOW=1\` budget is available in \`./validate.sh\` for faster
static + E2E checks.` — it dangles off the main sentence after a semicolon.

## FINDING 3 — Contract result requires `;` → `.` punctuation fix

The **work-item contract** is authoritative and specifies the desired paragraph
result verbatim:

> '...each test starts a fresh isolated tmux server and sources the user config).
> The suites cover the PRD §15 clusters:'

i.e. the trailing `;` after `config)` MUST become a `.` so that "The suites
cover the PRD §15 clusters:" starts a clean new sentence. (The
`bugfix_findings.md` "Fix" note says "ends at '...sources the user config);'" —
that variant would leave the grammatically-broken `; The suites` and is
SUPERSEDED by the work-item contract's explicit period result.)

## FINDING 4 — Unique, ASCII-only edit anchor (lowest-risk `oldText`)

The substring below is **unique** in the file (`VALIDATE_SKIP_SLOW` appears only
here) and is **pure ASCII** (no en-dash / § bytes to mishandle):

```
sources the user config); a `VALIDATE_SKIP_SLOW=1`
budget is available in `./validate.sh` for faster static + E2E checks. The suites
```

→ replace with:

```
sources the user config). The suites
```

This one edit (a) deletes the `VALIDATE_SKIP_SLOW` / `./validate.sh` clause,
(b) converts the dangling `; ` into `. ` (contract result), and (c) preserves
" The suites cover the PRD §15 clusters:" (which follows the matched region and
is NOT part of `oldText`). After the edit the two physical lines collapse into a
single ~94-char line; markdown renders identically regardless of wrap width.

## FINDING 5 — `tests/run.sh` has NO `VALIDATE_SKIP_SLOW` handling

```text
$ grep -n 'VALIDATE_SKIP_SLOW' tests/run.sh
(no match)
```

So the advertised "budget" never existed. The real entry point
`bash tests/run.sh` (README line 174) is correct and documented on the line
immediately above the broken paragraph — it must NOT be touched.

## FINDING 6 — Neither token is referenced anywhere else

```text
$ grep -rn 'validate\.sh\|VALIDATE_SKIP_SLOW' tests/ scripts/ plugin.tmux
(no match)
```

So removing the README sentence is the **complete** fix — no dangling references
to clean up elsewhere, no scripts to update, no `options.sh`/state keys. CHANGELOG
sync (adding the "Fix:" entry for Issue 5) is deliberately deferred to a later
task (P1.M3.T1.S1) and is out of scope here.

## FINDING 7 — No regression test needed (doc-only; contract is explicit)

The work-item contract states `MOCKING: N/A — documentation-only change` and
`OUTPUT: README.md Validation section no longer references validate.sh or
VALIDATE_SKIP_SLOW.` A grep-based assertion test would be (a) out of scope, (b)
a one-time prose error unlikely to recur via code, and (c) a parallel-conflict
risk (P1.M2.T1.S1 edits `test_functional.sh`, P1.M2.T2.S1 edits
`test_preview.sh`). Validation is therefore a **grep self-check** on README.md,
not a test-suite addition.

## FINDING 8 — Disjoint from all parallel / sibling tasks

- P1.M2.T1.S1 → `scripts/renderer.sh` + `tests/test_functional.sh` (Issue 3).
- P1.M2.T2.S1 → `scripts/preview.sh` + `tests/test_preview.sh` (Issue 4).
- **This task** → `README.md` (Validation section, ~lines 180–183) only.

No shared file. P1.M3.T1.S1 will later edit the README **overview** section +
CHANGELOG (different region, sequenced after P1.M2) — this task edits only the
Validation paragraph and must not pre-empt the changelog entry.

## FINDING 9 — Constraints from the contract (anti-patterns)

- Do **NOT** remove/change the `bash tests/run.sh` command (README line 174).
- Do **NOT** create a `validate.sh` wrapper (PRD offered two options; doc-removal
  is in-scope per the SOW, shipping a wrapper is a feature addition, out of pass).
- Do **NOT** touch any other README section, `tests/run.sh`, CHANGELOG, or any
  script. The change is confined to the single Validation paragraph.
