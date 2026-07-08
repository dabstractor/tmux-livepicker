# Research Findings — P2.M1.T2.S1 (rename command-prompt + do-rename + input dispatch)

Empirical probes run on the installed tmux 3.6b via isolated `-L` sockets (the
project's established method). All facts below were observed live unless marked
"PRD-documented".

## FINDING 1 — session id is stable across rename AND targetable by the bare `$N` form

- `#{session_id}` is exposed by `list-sessions -F '#{session_id} #{session_name}'`
  → `$0`, `$1`, … (one per session). It does NOT change when the session is
  renamed (alpha `$0` → renamed to gamma → STILL `$0`).
- Targeting by the **bare** id works: `display-message -p -t '$0' '#{session_name}'`
  → the name; `has-session -t '$0'` → rc 0; `rename-session -t '$0' 'NEW'` works.
- IMPORTANT asymmetry: `display-message -p -t '=alpha' '#{session_id}'` returns
  EMPTY (the `=name` target does not resolve `#{session_id}` reliably without an
  attached client). So capture the id from `list-sessions -F`, NOT from
  display-message against a name target.
- `display-message -p -t '$sid' '#{session_name}'` works **with no attached
  client** (the explicit session target makes it client-independent) and returns
  the FULL name (handles spaces in the result, unlike an awk field split).
- Bash note: when `sid="$0"` (a literal string), `"$sid"` is NOT re-expanded by
  bash (no `$0` parameter injection) — tmux receives the literal `$0` and parses
  it as session-id 0. Safe.

## FINDING 2 — rename-session SANITIZES silently (rc=0, different name)

Observed on 3.6b (rename targeting by the stable id, read-back by id):

| input NEW       | rc | resulting name   | meaning                       |
|-----------------|----|------------------|-------------------------------|
| `a:b`           | 0  | `a_b`            | `:` → `_` (sanitized)         |
| `.dotstart`     | 0  | `_dotstart`      | leading `.` → `_` (sanitized) |
| `beta` (exists) | 1  | (unchanged)      | collision — rename NOT applied|
| `` (empty)      | 1  | (unchanged)      | invalid — rename NOT applied  |

- **rc=0 does NOT mean the name is unchanged** (the two sanitized cases return 0).
- Collision / invalid return **rc=1** and leave the session untouched (clean
  abort — nothing to revert). Collision message: `duplicate session: X`.
- CONCLUSION: detect sanitization by reading back the actual name AFTER a rc=0
  rename (via the stable session id) and comparing to `$NEW`.

## FINDING 3 — the robust do-rename detection sequence (session mode): reject + revert

The OUTPUT contract (§4) requires "sanitized/collision names abort with a message
and NO rename". So do-rename NEVER keeps a sanitized name — it rejects it (and
reverts if tmux already applied one). Pre-detect the documented rules for a clean
abort, plus a post-check that reverts any unpredicted sanitization:

```
# (a) PRE-detect the documented tmux sanitization rules (FINDING 2): abort BEFORE
#     renaming so NO rename occurs (matches OUTPUT §4; clear per-rule messages).
case "$NEW" in *:*) tmux display-message "livepicker: ':' is not allowed in a session name"; return 0 ;; esac
case "$NEW" in .*)  tmux display-message "livepicker: a session name cannot start with '.'"; return 0 ;; esac
# (b) capture the STABLE session id; rename targeting the bare id; rc!=0 = collision/invalid.
sid="$(tmux list-sessions -F '#{session_id} #{session_name}' | awk -v s="$S" '$2==s{print $1; exit}')"
[ -z "$sid" ] && return 0                       # S vanished (race) -> no-op
if ! tmux rename-session -t "$sid" "$NEW"; then  # rc!=0 -> collision/invalid, nothing renamed
    tmux display-message "livepicker: cannot rename '$S' to '$NEW' (in use or invalid)"
    return 0                                     # picker stays open, list UNCHANGED
fi
# (c) SAFETY NET: read the actual name back by id; if != NEW (unpredicted
#     sanitization), REVERT to $S via the id -> NO rename; never silent.
actual="$(tmux display-message -p -t "$sid" '#{session_name}')"
if [ "$actual" != "$NEW" ]; then
    tmux rename-session -t "$sid" "$S" 2>/dev/null || true
    tmux display-message "livepicker: '$NEW' is not a valid session name"
    return 0                                     # list UNCHANGED, picker stays open
fi
# (d) clean success (actual == NEW): rewrite STATE_LIST in place (S -> NEW);
#     index unchanged -> highlight stays; window id unchanged -> no re-link; refresh.
```

- WHY target by id (not `=S`): after a sanitized rename the session is named
  neither `$S` nor `$NEW`, so a name-target can't find it to revert / read back.
  The id is the only stable handle; it does NOT change across rename (FINDING 1).
- WHY revert (not keep): the OUTPUT contract explicitly wants "no rename" for
  sanitized names. Reverting restores the session to its original name so the
  list (still containing `$S`) stays consistent and the user can retry.
- `awk -v s="$S" '$2==s{...}'` fails if `$S` itself contains a SPACE (field
  split). That is consistent with the `%%` limitation (FINDING 6) — spaced
  session names can't be renamed through this flow anyway. Acceptable.
- REVERT is best-effort (`|| true`): a pathological race (another session taking
  `$S` in the ms between rename and revert) could leave the sanitized name; the
  pre-detect covers the common cases so this net rarely fires.

## FINDING 4 — window mode: rename-window does NOT change the index; names are NOT sanitized

- `rename-window -t 'drv:1' 'renamed-win'` → index stays `1` (only the name
  changes). So the picker's window-mode token (`session:window_index`, built by
  activate via `list-windows -a -F '#{session_name}:#{window_index}'`) is
  **UNCHANGED** by rename-window → **NO STATE_LIST rewrite in window mode**.
- Window names are NOT subject to session-name sanitization: `w:colon` stays
  `w:colon`; `.wdot` stays `.wdot`. So window-mode do-rename has NO
  sanitization-detection concern — just `rename-window -t "$token" "$NEW"`,
  check rc, refresh, keep highlight (index unchanged).
- "Same shape" (PRD §21.44) therefore means: resolve the highlighted token,
  rename-window, rc-check, refresh-client -S. No list edit, no actual-name read.

## FINDING 5 — command-prompt `%%` is the PRD-documented substitution primitive (PRD §13/§21/§16)

Not re-tested interactively (command-prompt is a client mode). Authoritatively
documented in the PRD and mirrored verbatim by sessionx's rename:

```
tmux command-prompt -I "$S" -p "Rename session:" \
  "run-shell '$CURRENT_DIR/session-mgmt.sh do-rename %%'"
```

- The OUTER string is double-quoted in bash → `$CURRENT_DIR` expands to the
  absolute scripts/ dir at call time; `%%` is left literal (no bash meaning).
- tmux's command-prompt replaces `%%` with the user's typed input on submit →
  `run-shell '<abs>/session-mgmt.sh do-rename <NEW>'` → run-shell word-splits →
  argv = (do-rename, NEW). Same dispatch shape as input-handler.sh `type $lp_c`.
- While the prompt is open it CAPTURES input (the livepicker key-table is
  effectively suspended); on submit OR escape tmux restores the livepicker
  table automatically → **no extra binding work** (confirmed by work item §1).
- Escape cancels → the template does NOT run → no do-rename. Empty submit →
  template runs with empty → do-rename "" → the `[ -z "$NEW" ] && return 0`
  guard no-ops.
- command-prompt is a CLIENT command (needs an attached client). The picker is
  always invoked from an attached client (the user pressed C-r); the test
  harness supplies one via `attach_test_client`. No `-t` target is needed in the
  single-client target environment (PRD §2 non-goals).

## FINDING 6 — `%%` escaping limitation (names with special chars / spaces break)

- The unquoted `%%` inside the single-quoted run-shell word-splits on submit.
  Names containing `'`, `"`, `` ` ``, `$` (PRD §16) AND spaces break the
  substitution (a space → `do-rename foo bar` → argv[2]=`foo` only).
- Use the EXACT PRD template (unquoted `%%`). Do NOT "improve" it by wrapping
  `%%` in quotes — that trades one breakage class for another (a `"` in the name
  breaks the wrapper) and deviates from the PRD contract. The limitation is
  documented and rides to P4. tmux rejects `:` in session names anyway.

## FINDING 7 — STATE_LIST format + in-place rewrite

- STATE_LIST is newline-joined with EMBEDDED `\n` and NO trailing `\n` (activate
  captures it via `$(tmux list-sessions …)` which `$()` strips the trailing
  newline). `set_state` (tmux set-option -g) preserves embedded newlines
  (livepicker.sh FINDING 3).
- Session-mode rewrite = replace the one line equal to `$S` with `$actual`.
  Use `mapfile -t lines < <(printf '%s' "$list")` (process substitution — an
  empty list is a truly empty array, NOT `[""]`; renderer FINDING 3), edit the
  matching index in place, then rebuild with a join loop that emits NO trailing
  newline (mirror activate's format). Session names are unique → exactly one
  match. Whole-line compare handles spaces in names (unlike awk field split).

## FINDING 8 — highlight + preview are UNAFFECTED by a rename (no re-link)

- rename-session does NOT change the window id. The linked preview
  (`@livepicker-linked-id`) stays valid → NO preview re-link / re-sync needed.
- The renamed session stays at the SAME list position (rename doesn't reorder) →
  `@livepicker-index` is left UNCHANGED → the highlight naturally stays on it.
  The only redraw needed is `refresh-client -S` so the §19 renderer reprints the
  new name in the tab.

## FINDING 9 — input-handler.sh `rename)` is a thin delegate

- input-handler.sh already sources options/utils/state/rank/layout and defines
  `$CURRENT_DIR`. The `rename)` branch is a one-line delegate:
  `"$CURRENT_DIR/session-mgmt.sh" rename; return 0`.
- session-mgmt.sh re-sources the libs (it is its own process under run-shell,
  exactly like restore.sh is called from input-handler via
  `"$CURRENT_DIR/restore.sh" keep`). The small re-source overhead is acceptable
  (rename is a one-shot, not per-keystroke).
- The `delete)` dispatch branch is P2.M1.T2.S2's scope — leave a seam comment.

## FINDING 10 — session-mgmt.sh follows §P1 (executable entry point)

- NEW file `scripts/session-mgmt.sh`: `#!/usr/bin/env bash`, `# shellcheck
  disable=SC1091,SC2153`, `set -u` (NOT -e; rename-session legitimately returns
  rc≠0 on collision and must NOT abort the script), `CURRENT_DIR` resolve, source
  options/utils/state/rank (NOT layout — no viewport/scroll work here).
- Driver: `session_mgmt_main "$@" || exit 1; exit 0` (mirrors restore.sh /
  input-handler.sh / livepicker.sh). Must be `chmod +x` (all entry points are
  +x; sourced libs are not).
- `case "$action"` dispatches `rename` / `do-rename`, with a `*)` default
  no-op + a seam comment for `delete`/`do-delete` (P2.M1.T2.S2).
