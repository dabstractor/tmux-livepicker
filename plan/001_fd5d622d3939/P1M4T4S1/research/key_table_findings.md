# Research Findings — P1.M4.T4.S1: build livepicker key table

All findings verified **live** on an isolated tmux 3.6b socket (PATH-wrapper
shim, `tmux -L <sock>`). Zero impact on the live server. Each test self-cleaned.

The 6 findings below are the load-bearing facts for the S1 implementation block.
Read them before writing/editing the block.

---

## FINDING 1 — Copy bindings via `source-file`, NEVER `tmux $line` word-split  [SHOWSTOPPER]

`tmux list-keys -T prefix` emits one binding per line in the form:
```
bind-key    -T prefix KEY   COMMAND...
```
(note: column-aligned with MULTIPLE spaces; the COMMAND may be arbitrarily
complex — braces `{ }`, nested double-quotes, `\;` sequences, etc.).

**The naive copy** — `tmux $line` (word-split the line back into tmux args) —
**BREAKS** on complex commands. Verified failure: the tubular `>` prefix binding
is a giant `display-menu -T "..." { ... C-r { ... set-buffer "#{q:mouse_word}" } ... }`.
Word-splitting it produced:
```
command set-buffer: too many arguments (need at most 1)
```
(bash consumed the inner quotes during expansion; tmux saw the mangled args).
C-r did NOT get copied.

**The correct copy** — write the rewritten lines to a temp file and
`tmux source-file "$TF"`. tmux's OWN command parser reads the file line-by-line
and re-parses each binding with the SAME parser that defined it (so braces,
quotes, and `\;` survive intact). Verified: **129/129** prefix bindings copied,
including the `>` display-menu monster AND C-r (`source-file`). rc=0, no errors.

**Form:**
```bash
TF="$(mktemp)"
{
	tmux list-keys -T prefix 2>/dev/null | sed 's/-T prefix/-T livepicker/'
	tmux list-keys -T root   2>/dev/null | sed 's/-T root/-T livepicker/'
} | grep -vE -- "<skip pattern>" > "$TF"
tmux source-file "$TF"
rm -f "$TF"
```
The `sed` rewrites ONLY the first `-T <table>` on each line — and that first
occurrence is ALWAYS the table spec (line format is `bind-key [-r] -T table KEY
cmd...`), so it is unambiguous even if the command text contains `-T prefix` as
a substring. Verified (display-menu line copied with its inner `-t`/format args
untouched).

---

## FINDING 2 — ORDER: copy FIRST, explicit binds LAST  [SHOWSTOPPER]

The user's `prefix`/`root` tables contain bindings for MANY of the keys the
picker wants: `Enter`, `Down`, `Up`, `a` (rare), etc. If the explicit picker
bindings are applied FIRST and the copy SECOND, **the copy overwrites the picker
keys** — e.g. `Down` reverts to the user's `select-pane -D`, breaking nav.

Verified failure (explicit-then-copy order): `Down`, `Up`, `Enter`, `BSpace`,
`a`, `-`, `/` ALL came back as 0 matches for the picker command (overwritten);
only `Escape` and the skipped `C-M-Tab` survived.

**Correct order** (verified, 14/14 assertions pass):
1. COPY prefix + root → livepicker (skip next/prev keys) via source-file.
2. BIND explicit picker keys (typing/actions/nav) — these OVERRIDE any copied
   same-key binding because they run LAST.
3. SWITCH `key-table` to livepicker.

**This is also WHY the item's "skip next-key/prev-key" is necessary but NOT
sufficient**: the skip handles C-M-Tab/C-M-BTab (so the compound swap-window
command isn't even briefly in the table), but Down/Up/Enter/etc. are protected
by ORDERING (explicit-last), not by the skip. Implement BOTH: skip next/prev in
the copy (item spec) AND bind explicit last (robustness).

---

## FINDING 3 — `set-option -g key-table livepicker` (with `-g`); standalone `key-table` cmd does NOT exist

- `tmux set-option -g key-table livepicker` → rc=0, and
  `show-option -gv key-table` reflects `livepicker`. ✓ (global/session option).
- `tmux set-option key-table livepicker` (NO `-g`) → rc=0 BUT
  `show-option -gv key-table` still shows `root` (it set the session-scoped
  value, not the global that `-gv` reads). → **MUST use `-g`** to match the
  save/restore contract (`ORIG_KEY_TABLE` is saved via `tmux_save_opt
  key-table key-table` → `show-option -gqv`, i.e. GLOBAL; restore replays
  `-g`). Using `-g` here keeps the pair symmetric.
- `tmux key-table livepicker` → **`unknown command: key-table`** (rc=1) on
  3.6b. The `key-table` standalone command referenced in tmux_primitives §2 does
  NOT exist. Use `set-option -g key-table` exclusively.

---

## FINDING 4 — Skip pattern for next-key/prev-key in the copy

The skip must match the KEY token that follows `-T livepicker` (after sed
rewrote the table). The robust anchor (handles the variable column-align
whitespace AND ensures we match the whole key, not a substring):

```bash
grep -vE -- "-T livepicker[[:space:]]+(${NEXT_KEY}|${PREV_KEY})([[:space:]]|$)"
```

Verified: root's two compound bindings
(`C-M-Tab → swap-window -t +1 \; select-window -t +1` and `C-M-BTab → ... -t -1
...`) are BOTH filtered out (remaining count = 0). The `[[:space:]]|$` tail
anchor prevents a partial-key match (e.g. `C-M-Tab` would not accidentally match
a hypothetical `C-M-Table`). The `-` inside `C-M-Tab` is literal in regex
outside a character class — no escaping needed for the default keys.

**Known limitation:** if a user sets `@livepicker-next-key`/`prev-key` to a key
whose name contains regex metacharacters (e.g. `C-\`, `(`), the grep pattern
would mis-match. The defaults (C-M-Tab, C-M-BTab) and all realistic tmux key
names are safe. Discovery is explicitly OPTIONAL/best-effort per the item and is
NOT implemented (defaults cover this user's keys per PRD §8).

---

## FINDING 5 — All typing chars bind cleanly, including `-` (no `--` needed)

Verified rc=0 for every char in the typing set: `a`-`z`, `A`-`Z`, `0`-`9`, and
`-`, `_`, `.`, `/`. The `-` key (which looks flag-like) binds correctly without
a `--` separator:
```
tmux bind-key -T livepicker - run-shell "/abs/input-handler.sh type -"
```
→ `list-keys` confirms `bind-key -T livepicker - run-shell "..."`. tmux's
bind-key arg parser treats the first non-option token after `-T table` as the
key, so `-` is accepted. (A `--` before the key also works and is harmless, but
is NOT required.)

**Punctuation set decision:** PRD §8 / the item write the typing punctuation as
`-_. /`. Interpreted as single-character tmux keys (excluding the prose
whitespace separator), the set is **`-`, `_`, `.`, `/`** (4 chars). A literal
SPACE is NOT included: it would require the two-token key name `Space` and is an
edge case not clearly required by the PRD notation. (If space-as-filter-char is
later desired — e.g. to type-match the "job hunt" session — it is a one-line
addition: `tmux bind-key -T livepicker Space run-shell "$CURRENT_DIR/input-handler.sh type ' '"`.)

---

## FINDING 6 — `run-shell "PATH type CHAR"` quoting + input-handler contract

The PRD §8 binding form:
```bash
tmux bind-key -T livepicker "$KEY" run-shell "$CURRENT_DIR/input-handler.sh type $CHAR"
```
Verified: bash expands `"$CURRENT_DIR/input-handler.sh type $CHAR"` to ONE
string (e.g. `/abs/scripts/input-handler.sh type a`), passed to tmux as the
single argument after `run-shell`. tmux stores it (list-keys shows it
double-quoted) and, on keypress, runs `/bin/sh -c "<that string>"`. The
input-handler therefore receives `type` as `$1` and the char as `$2`.

**Implication for P1.M6 (input-handler.sh — NOT this task):** it must parse
positionally (`action="$1"; char="$2"`), NOT with getopt/getopts, because chars
like `-` would otherwise be misread as flags. This task only STORES the binding;
input-handler.sh need not exist yet (the binding is inert until the key fires).

**`$CURRENT_DIR` (not `$SCRIPT_DIR`):** the existing `scripts/livepicker.sh`
computes `CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` = the
`scripts/` directory (T3 already references `$CURRENT_DIR/renderer.sh` for the
same reason). So input-handler.sh — which lives in `scripts/` — is reached as
`$CURRENT_DIR/input-handler.sh`. The item's "`$SCRIPT_DIR/scripts/input-handler.sh`"
phrasing assumes SCRIPT_DIR = repo root; the ACTUAL in-file variable is
`CURRENT_DIR` = scripts dir, so the path is `$CURRENT_DIR/input-handler.sh`.

---

## Full-flow proof (corrected order, 14/14 assertions pass)

Ran the complete S1 block (copy→explicit→switch) on the isolated socket:

```
key-table: [livepicker] (expect livepicker)            ✓
typing 'a' / '-' / '/' / '_'                           ✓ (4/4)
BSpace backspace / Enter confirm / Escape cancel       ✓ (3/3)
C-M-Tab next-session (NOT swap-window; 0 leak)         ✓
C-M-BTab prev-session                                   ✓
Down / Up / j / k  → next/prev-session (override)      ✓ (4/4)
user C-r (source-file) COPIED into livepicker          ✓
total livepicker bindings: 169
```

The `Down`/`Up` override assertions (1 each) are the proof that ORDER (copy
first, explicit last) is what makes "explicit takes precedence" actually true
for ALL explicit keys — not just the skipped next/prev keys.
