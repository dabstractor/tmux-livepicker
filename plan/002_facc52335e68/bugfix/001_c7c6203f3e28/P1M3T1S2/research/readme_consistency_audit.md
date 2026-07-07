# Research: README.md consistency sweep (P1.M3.T1.S2)

> **Methodology:** full read of `README.md` (220 lines), `git log` of the rev 002
> bugfix commits, and source inspection of the fixed `scripts/preview.sh`
> (Issue 1/2/4) and `scripts/input-handler.sh` (Issue 3) to confirm the actual
> shipped behavior each README section must match. This is a **Mode B
> changeset-level documentation sweep**: verify each feature/behavior section is
> consistent with the six code fixes; edit ONLY sections that are now stale.

## Scope — the 5 contract checks mapped to verified findings

| # | Contract check | README location | Verdict | Action |
|---|----------------|-----------------|---------|--------|
| (a) | No `link-window -a` reference | L159 "How it works" | ✅ CLEAN | none |
| (b) | Create behavior reflects name sanitization | L49-50 (story), L144-145 (usage) | ⚠️ GAP | ADD 1-sentence note |
| (c) | window-status tab doesn't claim `#S`/`#{session_name}` unsupported | L106 (config), L123 (Appearance) | ✅ CLEAN | none |
| (d) | Known limitations section properly placed/formatted | L167-177 | ✅ OK | none (verify only) |
| (e) | Features/Behavior overview consistent | Goals/Overview/How-it-works | ✅ CLEAN | none |

**Net:** ONE minimal edit (the (b) sanitization note). Everything else is already
consistent with the shipped code. This matches the contract's "Make minimal edits
— only update sections that are now inconsistent."

---

## (a) `link-window -a` — CLEAN (no edit)

`grep -n -- '-a\b\|link-window -a' README.md` finds NO `-a` flag reference
anywhere. The "How it works" section (L159) says only:

> "links the highlighted candidate's active window into your current session
> with `tmux link-window` and selects it with `select-window`"

No flag, no insertion-position claim. The fix (commit `16c53a0` "Fix preview
link-window mid-list index corruption"; `scripts/preview.sh:230`
`tmux link-window -s "$src_id" -t "$current_session:"` — NO `-a`) is therefore
already consistent with the README. Contract item 3a says "update it to describe
appending at the end" ONLY "if any mention exists" — none does, so **no edit**.
(The `@livepicker-preview-mode` row at L103 and the Performance note at L127
also say bare `link-window`/`select-window` — all clean.)

---

## (b) Create behavior + sanitization — THE ONE GAP (add a note)

**Current README text (consistent but silent on sanitization):**
- L12-13 (Overview): "Confirming lands you on the chosen session (optionally
  creating a new one from your filter query)".
- L25-26 (Goals): "Create on Enter. In session mode, with no match, Enter
  creates a session from your filter query."
- L49-50 (User stories — Create): "I type `newproj` (no match) and press
  `Enter`; a new `newproj` session is created and I am switched to it."
- L94 (config `@livepicker-create`): "create a new session from the query".
- L143-145 (Usage step 4): "it creates a session from your query and switches
  to it."

None of these is WRONG (you do land on a created session). But none mentions
that `.` (typeable — it is in the typeable set) is sanitized by tmux, and the
contract item 1 explicitly directs: "The create behavior section (if any) should
reflect that names are sanitized." Before the fix (Issue 3), a dotted query
`my.proj` was orphaned (`my_proj` created but the user stranded); after the fix
the user lands on the sanitized name.

**Verified fixed behavior** (`scripts/input-handler.sh:387-403`, commit
`6aea983` "Fix sanitized-name create orphan via -P -F capture"):

```bash
local z_target="" created="" new_session_args=(-d -P -F '#{session_name}' -s "$query")
...
created="$(tmux new-session "${new_session_args[@]}" 2>/dev/null)"
if [ -n "$created" ]; then
    _confirm_land_on_session "$created"
```

- `new-session -P -F '#{session_name}'` prints the ACTUAL name tmux created
  (sanitized: `my.proj` → `my_proj`) to stdout; the code lands on `$created`.
- On a sanitized-name COLLISION (the sanitized name already exists), `new-session`
  returns rc=1 + empty stdout → `created=""` → cancel (NO orphan session).
- So the user-visible contract is: **type a query; if it has no match you land on
  a freshly created session derived from it; characters tmux disallows in session
  names (such as `.`) are sanitized (e.g. `my.proj` → `my_proj`) and you still
  land on it.**

**Edit:** add ONE concise sentence to the Create **user story** (L49-50), the
most natural home for a user-facing behavior note. Keep it minimal and
accurate (no implementation detail — no `-P -F`, no "orphan"). Example wording
(anchored on the exact existing two-line bullet):

```
- **Create.** I type `newproj` (no match) and press `Enter`; a new `newproj`
  session is created and I am switched to it. Characters tmux disallows in
  session names (such as `.`) are sanitized — `my.proj` becomes `my_proj` — and
  you still land on the created session.
```

Do NOT also edit Overview/Goals/Usage/config-row — one mention in the Create
story is sufficient and keeps the diff minimal (contract: "minimal edits").
The other create mentions stay as-is (they are not inaccurate).

---

## (c) window-status tab + session specifiers — CLEAN (no edit)

`grep -n '#S\|session_name\|window-status\|sentinel' README.md` shows the README
NEVER claims `#S` / `#{session_name}` is unsupported. To the contrary:
- L106 (config `@livepicker-tab-style`): "`window-status` (reuse the theme's
  `window-status-current-format` / `window-status-format` so picker tabs match
  your window tabs; falls back to `plain`)."
- L123 (Appearance): "the picker renders its items through the theme's own ...
  formats, so the tabs read as part of the status bar **under any theme** ...
  If the theme format cannot be resolved, the picker falls back to `plain`."

Before the Issue 5 fix (commit `3a67ae1` "Fix sentinel session name for stable
specifier swap"), this "any theme" claim was PARTIALLY FALSE for themes using
session-context specifiers (`#{session_name}` expanded to the sentinel's unique
session name). The FIX made the README's broad claim TRUE — the code was brought
into line with the README, not the reverse. So **no README edit** for (c); the
section is now MORE accurate, not stale.

(The fix itself lives in `scripts/livepicker.sh` + `scripts/renderer.sh` — a
stable sentinel session name + a second renderer swap. The README intentionally
does not document the sentinel mechanism (internal); the user-facing
"matches any theme, falls back to plain" wording is correct and unchanged.)

---

## (d) Known limitations section — OK (verify only, no edit)

The `### Known limitations` subsection (L167-177) was added by P1.M2.T3.S1
(commit `bec7369` "Document detached candidate resize limitation", Issue 6).
Audit:
- **Placement:** sits under `## How it works` (L156), before `## Compatibility`
  (L178). Defensible — it qualifies the preview mechanism described just above.
  It could alternatively be a top-level `##` section, but as a behavior caveat
  of "how it works" the current placement is consistent and intentional.
- **Heading level:** `###` — matches the other subsections in the file
  (`### Appearance` L121, `### Performance` L125 under Configuration). Consistent.
- **Content:** one bullet, "Detached candidate windows are resized during
  preview", accurately describing Issue 6 (tmux `window-size auto` resizes the
  shared linked window to the driver's dimensions; on unlink a detached
  candidate shrinks to the no-client default; pane count + window id intact).
  Offers the mitigation `@livepicker-preview-mode snapshot`. Accurate + useful.
- **Formatting:** well-formed markdown bullet; backticked option name.

**No edit.** The section is properly placed, formatted, and consistent. The
implementer should CONFIRM via the grep gates in Validation §1 (exactly one
`### Known limitations`, under `## How it works`) but no rewrite is expected.

---

## (e) Features / Behavior overview — CLEAN (no edit)

Reviewed Goals (L18-30), Non-goals (L32-38), User stories (L40-52), Overview
(L6-16), How it works (L156-177), Compatibility (L178-194). No stale claims:
- Goals "Exact restore" / Overview "byte-for-byte restored" — now TRUE on the
  default path (Issue 1 fixed the index shift that violated exact restore).
- "Zero history pollution" — unaffected (no fix touched the session-switch
  invariant).
- "Live, in-place preview ... every pane" — unaffected (Issue 1 only changed
  insertion position, not the all-panes property).
- No mention of `-a`, no mention of sentinel internals, no claim that dotted
  names fail to create.

**No edit.** All overview/feature sections are consistent with the shipped code.

---

## Commit evidence (all six fixes landed before this doc sweep)

```
bec7369 Document detached candidate resize limitation          # Issue 6 (README) — P1.M2.T3.S1
3a67ae1 Fix sentinel session name for stable specifier swap    # Issue 5 — P1.M2.T2.S1
99d5137 Close deferred-preview TOCTOU race with third seq guard# Issue 4 — P1.M2.T1.S1
8a35d4b Add sanitized-name create landing regression test      # Issue 3 test — P1.M1.T3.S2
6aea983 Fix sanitized-name create orphan via -P -F capture     # Issue 3 — P1.M1.T3.S1
2c12943 Add window-mode self-session duplicate guard test      # Issue 2 test — P1.M1.T2.S2
70a50e3 Fix self-session guard for window-mode duplicate link  # Issue 2 — P1.M1.T2.S1
f37e3ee Add multi-window index preservation tests              # Issue 1 test — P1.M1.T1.S2
16c53a0 Fix preview link-window mid-list index corruption      # Issue 1 — P1.M1.T1.S1
```

All code/test fixes are COMPLETE. P1.M3.T1.S1 (parallel) edits CHANGELOG.md.
This task (S2) edits README.md only — and, per the audit, needs exactly ONE
minimal addition (the (b) sanitization note). README already reflects Issues
1/2/4/5/6 correctly; only Issue 3's user-facing sanitization behavior is
undocumented.

## Sources
- `README.md` (220 lines — the file under audit; full read).
- `scripts/preview.sh:230` (`link-window -s "$src_id" -t "$current_session:"` — no `-a`).
- `scripts/input-handler.sh:387-403` (create-on-confirm `-P -F '#{session_name}'` capture).
- `git log` (the nine commits above).
- `plan/002_facc52335e68/bugfix/001_c7c6203f3e28/architecture/system_context.md`
  (file map L12-21; Issue 1/2/3 verified behavior).
- PRD.md (READ-ONLY) §6 Confirm, §7, §9, §13, §15, §17 (cross-refs only).
