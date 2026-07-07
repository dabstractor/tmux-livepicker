# Docs-sync findings (P1.M3.T3.S1)

Research notes for the README.md + CHANGELOG.md documentation task. The two
features (§17 `@livepicker-tab-style`, §18 `@livepicker-preview-defer`) are
fully implemented and tested by the sibling tasks; this task writes user-facing
docs only.

## 1. Current state of the two target files

- `README.md` has a 19-row config table (lines 92-110). It is MISSING both new
  options. PRD §11 order is: `preview-mode`, `preview-defer`,
  `suppress-window-hook`, `tab-style`, `fg`, `bg`, ... So:
  - `preview-defer` inserts between `preview-mode` (103) and
    `suppress-window-hook` (104).
  - `tab-style` inserts between `suppress-window-hook` (104) and `fg` (105).
- `CHANGELOG.md` has one `[Unreleased] — Initial implementation` section (line 6)
  covering plan-001. Neither new option is mentioned anywhere.
- Both files pre-date plan-002 (written in plan-001).

## 2. Exact table column widths (measured)

The config table is hand-padded:
- Option column content width = 34 chars (cell + trailing pad; the widest is
  `@livepicker-suppress-window-hook` = 32 + 2 backticks = 34, zero pad).
- Default column content width = 11 chars.
- Purpose column trailing-pad is cosmetic (markdown renders identically without
  it); provide purpose text without trailing padding.

Pre-padded new rows (verified to align):
```
| `@livepicker-preview-defer`        | `on`        | Defer the live preview to a background job so typing and navigation never wait on `link-window`/`select-window`; `off` restores the synchronous path for diagnosis. |
| `@livepicker-tab-style`            | `plain`     | `plain` (standalone `@livepicker-fg`/`bg`/`highlight-*`) or `window-status` (reuse the theme's `window-status-current-format` / `window-status-format` so picker tabs match your window tabs; falls back to `plain`). |
```

Single-edit insertion trick: anchor on the unique `@livepicker-suppress-window-hook`
row and replace it with [preview-defer row, suppress-window-hook row, tab-style
row]. That places preview-defer BEFORE it and tab-style AFTER it in one edit,
matching PRD §11 order exactly.

## 3. Defaults (authoritative, system_context.md §2)

- `@livepicker-tab-style` default = `plain` (default-OFF for the new look).
- `@livepicker-preview-defer` default = `on` (default-ON).

This asymmetry MUST be stated correctly in the CHANGELOG ("default-on
preview-defer / default-off tab-style").

## 4. Invariants to state (from implementing PRPs + PRD §4/§14/§16)

- Browsing fires NO `client-session-changed`. The preview uses `link-window` +
  `select-window` (NOT `switch-client`); only the single confirm-time
  `switch-client` fires it. So tmux-session-history and the toggle are untouched.
- `clear_all_state` tears down every picker state key on exit, INCLUDING the new
  ones: `STATE_TAB_CURRENT_TMPL` / `STATE_TAB_INACTIVE_TMPL` (§17) and
  `STATE_PREVIEW_SEQ` / `STATE_PREVIEW_TARGET` (§18). All four are in
  `_STATE_RUNTIME_KEYS` (landed in P1.M1.T1.S1 / P1.M2.T1.S1).
- The legacy paths remain: `plain` tab style is the shipped default; `preview-defer
  off` restores the synchronous preview (the escape hatch for diagnosis).
- §17 fallback: on any format-resolution failure (empty/unresolvable template, or
  the sentinel step fails) the picker falls back to `plain`, so the option never
  breaks the status bar (PRD §17 Fallback, §16).

## 5. write-tech-docs compliance — the em-dash trap (load-bearing)

- The skill's linter is at
  `/home/dustin/.pi/agent/skills/write-tech-docs/scripts/lint.sh`. It strips code
  blocks + inline code, then flags: em dashes (U+2014) and " -- ", banned
  tell-words (whole word, case-insensitive), and prose paragraphs > 100 words.
- CRITICAL: the EXISTING files already contain em dashes (README ~20, CHANGELOG
  ~10). So `bash lint.sh README.md` does NOT exit 0 today and will not after this
  scoped edit, because the pre-existing em dashes remain. Rewriting all of them is
  OUT OF SCOPE (the task adds two features' docs, not a whole-file restyle).
- THEREFORE the validation gate is: the NEW prose (the two table rows, the
  Appearance/Performance notes, the new CHANGELOG section) contains ZERO em dashes
  and ZERO tell-words. Verify by running the linter and confirming every reported
  hit is on a PRE-EXISTING line, OR by grepping only the added lines.
- Header separator choice: the existing `[Unreleased] — Initial implementation`
  header uses an em dash. The new section header MUST avoid the em dash to comply
  with the skill. Use a colon: `## [Unreleased]: theme-matched tabs and deferred
  preview`. This deliberately diverges from the pre-existing `—` header style,
  which the task does not ask us to rewrite.
- Tell-words to avoid in new prose: powerful, robust, elegant, seamless,
  comprehensive, leverage, utilize, unlock, empower, streamline, elevate, delve,
  blazing-fast, intuitive, effortless, etc. (full list in the skill). Use concrete
  verbs: render, defer, redraw, fall back, restore, tear down.
- Inline code (`link-window`, `select-window`, `run-shell -b`, `@livepicker-*`,
  `window-status-current-format`, `clear_all_state`) is stripped before the
  tell-word/em-dash check, so it is never flagged. Keep tmux primitives and option
  names in backticks.

## 6. Forbidden edits (scope guard)

- Do NOT edit `PRD.md` (READ-ONLY, owned by humans).
- Do NOT edit `tasks.json`, `prd_snapshot.md`, `.gitignore`, any `scripts/`, or
  any `tests/` file. This task touches ONLY `README.md` and `CHANGELOG.md`.
- Do NOT restate the whole plugin; right-size to the two new options.

## 7. README notes placement

After the "Set any option before the plugin loads" code block (the `set -g
@livepicker-highlight-bg 'magenta'` block, ~line 115) and before `## Usage`.
Add `### Appearance` and `### Performance` as subsections of `## Configuration`
(both new options are discovered/configured there, near their table rows).
Anchor the edit on the unique `set -g @livepicker-highlight-bg 'magenta'\n```\n\n##
Usage` sequence.
