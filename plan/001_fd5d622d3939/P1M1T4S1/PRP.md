# PRP — P1.M1.T4.S1: plugin.tmux — bind @livepicker-key (prefix table) + unset guard

---

## Goal

**Feature Goal**: A TPM/`run-shell`-loadable **entry point** `plugin.tmux` that,
when sourced by tmux (on `run-shell` / TPM load), reads the user's
`@livepicker-key` option and — if set — installs a **prefix-table** key binding
(`tmux bind-key "$KEY" run-shell "$CURRENT_DIR/scripts/livepicker.sh"`, NO `-n`,
NO `-T`) pointing at the activate script. If the key is unset/empty, it prints a
friendly `display-message` and binds nothing, exiting 0 so the plugin still loads
cleanly. This is the top of the PRD §5 data flow (`plugin.tmux → binds prefix +
@livepicker-key → scripts/livepicker.sh`).

**Deliverable**: The single file `plugin.tmux` at the **repository root** (NOT in
`scripts/` — it is the plugin entry point TPM/tmux invokes by name). Created
executable (`chmod +x`). Mirrors `tmux-session-history/session_history.tmux`
verbatim in structure (CURRENT_DIR idiom, inline option read, option-driven
`bind-key`). Depends on `scripts/options.sh` (P1.M1.T1.S1 — complete) for `get_opt`.

**Success Definition**:
- `bash -n plugin.tmux` passes; `shellcheck plugin.tmux` is clean (0 findings).
- `plugin.tmux` is executable (`-rwxr-xr-x`) and has shebang `#!/usr/bin/env bash`.
- **Mock validation (set-key branch):** executing plugin.tmux with a fake `tmux`
  that reports `@livepicker-key=Space` emits EXACTLY one bind-key invocation —
  `bind-key Space run-shell <ABS_PLUGIN_DIR>/scripts/livepicker.sh` — into the
  **prefix** table (no `-n`, no `-T` token anywhere), and ZERO `display-message`
  calls, and exits 0.
- **Mock validation (empty-key branch):** executing plugin.tmux with `@livepicker-key`
  unset emits EXACTLY one `display-message 'tmux-livepicker: set @livepicker-key to activate'`,
  ZERO `bind-key` calls, and exits 0.
- **Live spot-check (already done, see research):** `tmux bind-key 0 run-shell /tmp/...`
  with no `-T`/`-n` lands in `list-keys -T prefix` (NOT root) — proves the
  default-table semantics the contract relies on.

## User Persona (if applicable)

**Target User**: The tmux/TPM plugin loader and, transitively, the end user.
Mode A (internal entry point) — no user-facing surface beyond the key binding and
the one display-message. Install/usage docs are deferred to README P1.M8.T1.S1.

**Use Case**: On `tmux.conf` load (or `prefix C-r` reload), tmux `run-shell`s
`plugin.tmux`. The user, having pre-declared `@livepicker-key Space`, can now press
`C-Space` (root → prefix table, tubular) then `Space` to launch the picker.

**Pain Points Addressed**:
- (a) Without an entry point, the plugin has no key binding — it cannot be
  activated at all. This is the single seam between "plugin installed" and
  "plugin usable."
- (b) A naive `bind-key -n "$KEY" ...` (root table) would **shadow tubular's
  `C-Space`** root binding and break prefix entry entirely (research FINDING 3).
  The contract's prefix-table bind (default `bind-key`, no `-n`) is the only
  correct target.
- (c) Without the unset-guard, a user who hasn't set `@livepicker-key` gets a
  silent no-op or an obscure `bind-key` error on load. The guard emits a clear
  `display-message` and loads cleanly.

## Why

- **The activation seam.** This is the fourth and final foundation piece
  (options → utils → state → **plugin.tmux**). PRD §5 data flow starts here:
  `plugin.tmux → binds prefix + @livepicker-key → scripts/livepicker.sh`. Until
  this binding exists, none of P1.M2–P1.M6 (renderer, preview, activate,
  restore, input-handler) can be reached by the user. It is the literal top of
  the call graph.
- **The prefix-table correctness rule is load-bearing.** `prefix` is `None`;
  tubular binds `C-Space` in the **root** table to switch INTO the prefix table
  (system_context §5, research FINDING 3). `@livepicker-key Space` is a
  **prefix-table** binding. Therefore plugin.tmux MUST bind into the prefix table
  (the default for `bind-key` with no `-T`/`-n` — research FINDING 1). Using `-n`
  (root) would shadow tubular's `C-Space` and break the user's entire prefix
  flow. This is the single most consequential line in the file.
- **Mirror the cleanest sibling.** The contract names `session_history.tmux` as
  the template (CURRENT_DIR idiom, inline option read, option-driven `bind-key`,
  reload-safe). That file is 38 lines, no strictness beyond what sourced helpers
  bring, idempotent re-bind. plugin.tmux is structurally a strict subset of it.
- **Foundation for M4 (activate).** `scripts/livepicker.sh` (P1.M4.T1.S1) is the
  bind target. It does not exist yet — and that is FINE: `bind-key ... run-shell
  <path>` binds the path as a string; tmux only resolves/executes it when the key
  is pressed. So plugin.tmux can be written and validated before livepicker.sh
  exists (the mock validates the BIND command string, not the target's execution).

## What

A single executable Bash entry point at the repo root that:

1. Computes `CURRENT_DIR` via the canonical sibling idiom (resolves whether
   executed or sourced).
2. Sources `scripts/options.sh` (P1.M1.T1.S1) to obtain `get_opt`.
3. Reads `KEY="$(get_opt "@livepicker-key" '')"` — empty string if the user
   hasn't set the option (this empty default IS the guard).
4. **Guard:** if `KEY` is empty → `tmux display-message 'tmux-livepicker: set @livepicker-key to activate'`
   then `exit 0` (bind nothing; load cleanly).
5. **Bind:** else → `tmux bind-key "$KEY" run-shell "$CURRENT_DIR/scripts/livepicker.sh"`
   (prefix table by default — NO `-n`, NO `-T`).
6. `exit 0` (defensive: guarantees clean load even if the key name is invalid and
   `bind-key` warns).

### Success Criteria

- [ ] File exists at `./plugin.tmux` (repo root, NOT `scripts/`).
- [ ] Shebang `#!/usr/bin/env bash`; file is executable (`chmod +x`; `-rwxr-xr-x`).
- [ ] Body: `CURRENT_DIR` idiom → `source options.sh` → `get_opt "@livepicker-key" ''`
      → empty-guard (`display-message` + `exit 0`) → `tmux bind-key "$KEY" run-shell "$CURRENT_DIR/scripts/livepicker.sh"` → `exit 0`.
- [ ] **NO** `set -e` anywhere (contract: "tmux bind may warn"). `set -u` is OK
      (inherited from options.sh; plugin.tmux is set -u-safe — see Known Gotchas).
- [ ] **NO** `-n` and **NO** `-T` flag on the `bind-key` (prefix table is the default).
- [ ] The display-message text is byte-exact:
      `tmux-livepicker: set @livepicker-key to activate`.
- [ ] `bash -n plugin.tmux` → exit 0, no output; `shellcheck plugin.tmux` → 0 findings.
- [ ] Mock validation: both branches emit exactly the expected command set (see
      Validation Loop §2); the bind branch's command has no `-n`/`-T` token.
- [ ] `shellcheck source=scripts/options.sh` directive present (so shellcheck can
      resolve `get_opt` and not emit SC1090/SC2154).

## All Needed Context

### Context Completeness Check

_Pass_: A developer who has never seen this repo can implement plugin.tmux from
(a) the verbatim file body in the Implementation Blueprint, (b) the two
load-bearing facts (default-table = prefix [FINDING 1]; `-n` shadows tubular's
C-Space [FINDING 3]), and (c) the mock-validation commands. Every behavior is
verified live on 3.6b in the research findings.

### Documentation & References

```yaml
# MUST READ — the contract's named template (mirror its structure verbatim)
- file: /home/dustin/.config/tmux/plugins/tmux-session-history/session_history.tmux
  why: The cleanest sibling entry point. plugin.tmux is a structural SUBSET of it:
       CURRENT_DIR idiom (line 9), inline get_tmux_option read (lines 14-18 +
       27-30), option-driven `tmux bind-key "$key" run-shell "$SCRIPT ..."` (lines
       32-35), reload-safe idempotent re-bind. Copy the SHAPE; swap the option name
       and the bind target.
  pattern: |
    CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    get_tmux_option() { local value; value="$(tmux show-option -gqv "$1")"; [ -n "$value" ] && echo "$value" || echo "$2"; }
    toggle_key="$(get_tmux_option '@session-history-toggle-key' 'L')"
    [ -n "$toggle_key" ] && tmux bind-key "$toggle_key" run-shell "${SCRIPT} toggle ..."
  gotcha: session_history.tmux uses NO strictness mode and is executable (-rwxr-xr-x).
          plugin.tmux inherits `set -u` from the sourced options.sh (FINDING 7) —
          that is fine; do NOT add `set -e`.

# MUST READ — the INPUT dependency (already implemented; treat as a CONTRACT)
- docfile: plan/001_fd5d622d3939/P1M1T1S1/PRP.md
  why: Defines scripts/options.sh: get_opt(name, default) and the opt_* accessors.
       plugin.tmux sources it and calls get_opt "@livepicker-key" '' (the empty
       default is the guard). options.sh begins with `set -u` (NO -e) — sourcing
       it leaves set -u active in plugin.tmux (FINDING 7); plugin.tmux must be
       set -u-safe (it is: every var it reads is assigned first).
  section: "Implementation Patterns & Key Details" (the verbatim options.sh body)
  critical: get_opt's signature is get_opt(name, default) — the default is returned
            when the option is unset OR empty. Passing '' makes the guard fire on
            both "unset" and "set-to-empty-string".

# MUST READ — the empirical ground-truth for THIS file (10 live-verified findings)
- docfile: plan/001_fd5d622d3939/P1M1T4S1/research/plugin_tmux_findings.md
  why: FINDING 1 (bind-key with no -T/-n → PREFIX table, live-proven); FINDING 2
       (prefix Space currently = next-layout, will be overwritten — INTENDED;
       no collision with sessionx's prefix C-Space); FINDING 3 (prefix=None,
       C-Space is a ROOT-table tubular binding — using -n would shadow it);
       FINDING 4 (@livepicker-key=Space + @livepicker-fg=#ffffff are LIVE);
       FINDING 5 (session_history.tmux is executable → chmod +x REQUIRED);
       FINDING 6 (CURRENT_DIR idiom resolves under execution); FINDING 7 (set -u
       inherited from options.sh; do NOT add set -e); FINDING 8 (mock-validation
       strategy — fake tmux on PATH); FINDING 9 (inline get_opt vs opt_key);
       FINDING 10 (exit 0 semantics).
  critical: Read BEFORE writing the bind line. The -n-vs-default-table choice is
            the highest-consequence decision in the file.

# MUST READ — the prefix-key reality (grounds the "prefix table, not root" rule)
- docfile: plan/001_fd5d622d3939/architecture/system_context.md
  why: §5 "Prefix key reality" — prefix is None; tubular binds C-Space in the ROOT
       table (`switch-client -T prefix \; refresh-client`); @livepicker-key Space
       is therefore a PREFIX-table binding; the bind MUST use the default table
       (prefix), NOT -n (root). §1 confirms the two pre-declared options + the
       run-shell loading model. §9 mandates shell style (shebang, set -u, tabs,
       CURRENT_DIR idiom, quote everything).
  section: "§5 Prefix key reality", "§1 Project state", "§9 Shell style"

# MUST READ — sibling scout (prefix-table confirmation + reload-safety)
- docfile: plan/001_fd5d622d3939/architecture/sibling_plugins_and_env.md
  why: §8 "Prefix key & window-nav keybindings" — quotes the EXACT live bind
       (`bind-key -T root C-Space switch-client -T prefix \; refresh-client`),
       confirms prefix=None, and gives the verbatim correct plugin.tmux bind line
       (`tmux bind-key "$LIVEPICKER_KEY" run-shell "$CURRENT_DIR/scripts/livepicker.sh"`
       — default prefix table; "Do NOT use -n"). §2 documents the run-shell loading
       model (tmux-thumbs style). §10 confirms no collision with sessionx
       (C-Space vs Space, both prefix-table, different keys).
  section: "§8 Prefix key & window-nav keybindings", "§2 Plugin loading model", "§10"

# MUST READ — PRD sections selected for this work item
- docfile: PRD.md
  why: §11 Configuration options — @livepicker-key is "(required) ... If unset,
       the plugin prints a display-message and does not bind" (the guard contract,
       verbatim). §12 File layout — plugin.tmux sits at the repo ROOT
       ("bind @livepicker-key to activate"), NOT in scripts/. §5 Architecture /
       data flow — plugin.tmux is the top of the call graph
       ("binds prefix + @livepicker-key -> scripts/livepicker.sh").
  section: "§11 Configuration options (@livepicker-key row)", "§12 File layout", "§5 Architecture / Data flow"
```

### Current Codebase tree

```bash
tmux-livepicker/
  PRD.md
  plugin.tmux                 # ← DOES NOT EXIST YET (this task creates it, at repo ROOT)
  plan/001_fd5d622d3939/{architecture/*.md, tasks.json, prd_snapshot.md, prd_index.txt}
  plan/001_fd5d622d3939/P1M1T1S1/PRP.md          # options.sh contract (INPUT dep — COMPLETE)
  plan/001_fd5d622d3939/P1M1T2S1/{PRP.md, research/}   # utils.sh contract (COMPLETE)
  plan/001_fd5d622d3939/P1M1T3S1/{PRP.md, research/}   # state.sh contract (IN PARALLEL)
  plan/001_fd5d622d3939/P1M1T4S1/{PRP.md, research/}   # THIS work item
  scripts/
    options.sh   # EXISTS (P1.M1.T1.S1 complete) — get_opt + 18 opt_* accessors. THIS file's INPUT.
    utils.sh     # EXISTS (P1.M1.T2.S1 implemented) — tmux_* primitives (NOT used by plugin.tmux).
    # state.sh   # (P1.M1.T3.S1, in parallel) — NOT used by plugin.tmux.
    # livepicker.sh  # (P1.M4.T1.S1, future) — the BIND TARGET; does not need to exist yet.
  .gitignore
  # NOTE: NO plugin.tmux yet. NO test harness (P1.M7). NO scripts/livepicker.sh (P1.M4).
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
tmux-livepicker/
  plugin.tmux   # NEW (this task). ENTRY POINT (repo root). Reads @livepicker-key;
               #   empty → display-message + exit 0; else binds prefix-table key →
               #   scripts/livepicker.sh (the activate target). chmod +x. Mirrors
               #   session_history.tmux structure. Sources scripts/options.sh.
  scripts/
    options.sh   # (P1.M1.T1) INPUT dependency — get_opt. Unchanged by this task.
```

### Known Gotchas of our codebase & Library Quirks

```bash
# CRITICAL (research FINDING 1 + FINDING 3): the bind command MUST be
#   tmux bind-key "$KEY" run-shell "$CURRENT_DIR/scripts/livepicker.sh"
# with NO `-T` flag and NO `-n` flag. `bind-key` with neither targets the PREFIX
# table (live-proven). `-n` targets the ROOT table and would SHADOW tubular's
# `C-Space` root binding (switch-client -T prefix), breaking prefix entry for the
# WHOLE session. `-T prefix` is equivalent to the default but unnecessary; omit it
# to match the contract and session_history.tmux exactly.

# CRITICAL (research FINDING 5): plugin.tmux MUST be executable (chmod +x) and
# MUST have shebang `#!/usr/bin/env bash`. The loading model is
# `tmux run-shell '/path/to/plugin.tmux'`, which passes the path to `sh -c`; a
# non-executable file fails with "Permission denied". session_history.tmux is
# -rwxr-xr-x. This is a HARD requirement, not cosmetic.

# CRITICAL (contract): do NOT add `set -e`. A bad/invalid @livepicker-key (e.g. a
# typo like "Spce") makes `tmux bind-key` print `unknown key: Spce` to stderr and
# return non-zero. Under `set -e` that aborts plugin load (ugly). Without `set -e`
# the warning prints and the trailing `exit 0` still reports success — graceful
# degradation, exactly the contract's intent ("tmux bind may warn"). `set -u` is
# fine (inherited from options.sh; plugin.tmux is set -u-safe — FINDING 7).

# GOTCHA (research FINDING 2): binding `Space` (the live @livepicker-key)
# OVERWRITES tmux's default `prefix Space → next-layout`. This is INTENDED (the
# user explicitly set @livepicker-key Space). Do NOT try to "preserve" next-layout
# — that would defeat the binding. No collision with sessionx: sessionx is bound
# to `prefix C-Space`, a DIFFERENT key (sibling_plugins §10).

# GOTCHA: the bind TARGET (scripts/livepicker.sh) does NOT exist yet (P1.M4.T1.S1).
# That is FINE and BY DESIGN. `bind-key ... run-shell "<path>"` stores the path as
# a STRING; tmux only executes it when the key is pressed. plugin.tmux can be
# written, validated, and shipped before the activate script exists. (Do NOT
# create a stub livepicker.sh in this task — it is P1.M4's deliverable.)

# GOTCHA: plugin.tmux is an ENTRY POINT (executed via run-shell), NOT a sourced
# library. Unlike options.sh/utils.sh/state.sh (which must have NO side effects on
# source), plugin.tmux's WHOLE PURPOSE is the side effect of binding the key. It
# DOES compute CURRENT_DIR (sourced libraries must NOT — system_context §9). It
# DOES call `tmux` at top level. This is correct for an entry point.

# GOTCHA (research FINDING 7): sourcing options.sh activates `set -u` for the
# remainder of plugin.tmux. Every variable plugin.tmux reads (CURRENT_DIR, KEY) is
# assigned before use, so this is safe. Do NOT add an explicit `set -u` (redundant)
# and do NOT add `set +u` (would mask bugs). Leave strictness to options.sh.

# GOTCHA (shellcheck): plugin.tmux calls `get_opt`, which is defined in
# scripts/options.sh. Add a `# shellcheck source=scripts/options.sh` directive on
# the `source` line so shellcheck resolves it (avoids SC1090 "Can't follow non-
# constant source" and SC2154 "get_opt referenced but not assigned"). The mock
# validation (Validation §2) proves get_opt is actually defined at runtime.

# GOTCHA: `get_opt "@livepicker-key" ''` returns '' for BOTH "option unset" and
# "option set to empty string". The guard `[ -z "$KEY" ]` therefore fires on both
# — which is correct (an empty key is not a bindable key). Do not "improve" this
# with an `tmux_is_set` probe; the empty-default semantic is exactly the guard.

# STYLE: indent with TABS (system_context §9; sessionx/resurrect majority). Do
# NOT use 4-space indent. shfmt is NOT installed; verify manually with
# `grep -Pn '^    '`.
```

## Implementation Blueprint

### Data models and structure

No data model. plugin.tmux holds two local variables (`CURRENT_DIR`, `KEY`) and
emits exactly one of two tmux command sets depending on whether `KEY` is empty.
There are no functions, no constants, no state — it is a straight-line entry
point (mirrors session_history.tmux's flat top-level structure).

### Implementation Tasks (ordered by dependencies)

```yaml
Task 1: CREATE plugin.tmux — header + CURRENT_DIR + source options.sh
  - FILE: ./plugin.tmux  (REPO ROOT — NOT scripts/. PRD §12 file layout shows
    plugin.tmux at the root: "bind @livepicker-key to activate".)
  - SHEBANG: #!/usr/bin/env bash  (REQUIRED — run-shell executes via shebang).
  - HEADER COMMENT: one block stating purpose (entry point; binds @livepicker-key
    in the PREFIX table → scripts/livepicker.sh; unset-guard via display-message;
    mirrors session_history.tmux), the load-bearing rule (bind-key with NO -n/-T
    → prefix table; -n would shadow tubular's root C-Space — see system_context §5),
    and the dependency (sources scripts/options.sh for get_opt; the bind TARGET
    scripts/livepicker.sh is created by P1.M4 and need not exist yet).
  - CURRENT_DIR: the canonical sibling idiom, verbatim:
      CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    (research FINDING 6: resolves correctly under execution.)
  - SOURCE options.sh with a shellcheck directive:
      # shellcheck source=scripts/options.sh
      source "$CURRENT_DIR/scripts/options.sh"
  - NO `set -e` (contract). Do NOT add `set -u` (inherited from options.sh — FINDING 7).
  - STYLE: tabs; quote every expansion.
  - PLACEMENT: ./plugin.tmux

Task 2: READ the key + implement the unset-guard (IF branch)
  - READ: KEY="$(get_opt "@livepicker-key" '')"
    (inline form — mirrors session_history.tmux's inline get_tmux_option; the
    visible '' IS the guard semantic. FINDING 9.)
  - GUARD:
      if [ -z "$KEY" ]; then
          tmux display-message 'tmux-livepicker: set @livepicker-key to activate'
          exit 0
      fi
    (display-message text is BYTE-EXACT — PRD §11: "If unset, the plugin prints a
    display-message and does not bind." exit 0 so plugin loads cleanly.)
  - NOTE: `get_opt "@livepicker-key" ''` returns '' for both unset AND empty-string;
    the `-z` test covers both (correct — an empty key is not bindable).

Task 3: IMPLEMENT the bind (ELSE branch) + trailing exit 0
  - BIND (the load-bearing line — prefix table by DEFAULT, NO -n, NO -T):
      tmux bind-key "$KEY" run-shell "$CURRENT_DIR/scripts/livepicker.sh"
    (research FINDING 1: no -T/-n → PREFIX table. FINDING 3: -n would shadow
    tubular's root C-Space and break prefix entry.)
  - TRAILING exit 0 (defensive — research FINDING 10):
      exit 0
    (guarantees plugin load reports success even if @livepicker-key is an invalid
    tmux key name and `bind-key` printed `unknown key: ...`. Without set -e the
    warning does not abort; the explicit exit 0 ensures a clean exit code.)
  - COMMENT above the bind: state the prefix-table rule + why no -n.

Task 4: chmod +x  (REQUIRED — not cosmetic)
  - RUN: chmod +x plugin.tmux
  - VERIFY: ls -la plugin.tmux shows -rwxr-xr-x (research FINDING 5; mirrors
    session_history.tmux which is -rwxr-xr-x). The run-shell loading model passes
    the path to sh -c; a non-executable file fails "Permission denied".

Task 5: VALIDATE (Level 1 syntax/lint + Level 2 mock — no harness exists yet)
  - RUN: bash -n plugin.tmux           (expect exit 0, no output)
  - RUN: shellcheck plugin.tmux        (expect 0 findings; the source directive
    resolves get_opt so SC1090/SC2154 do not fire)
  - RUN: grep -Pn '^    ' plugin.tmux  (expect no output — tabs only)
  - RUN the throwaway mock-validation script (Validation Loop §2) — exercises BOTH
    branches (set-key → bind into prefix, no -n/-T; empty-key → display-message,
    no bind) against a FAKE tmux on PATH (zero live-server impact). Then DELETE
    the throwaway (do NOT commit a tests/ file — the harness is P1.M7.T1/T2).
  - VERIFY the live default-table fact is already confirmed (research FINDING 1:
    `bind-key 0 run-shell /tmp/...` → list-keys -T prefix shows it; cleaned up).
```

### Implementation Patterns & Key Details

```bash
#!/usr/bin/env bash
# plugin.tmux — tmux-livepicker entry point.
#
# Binds @livepicker-key (in the PREFIX table) to launch the picker. Mirrors the
# structure of tmux-session-history/session_history.tmux (CURRENT_DIR idiom, inline
# option read, option-driven bind-key, reload-safe idempotent re-bind).
#
# LOAD-BEARING RULE (system_context §5): prefix is None; tubular binds C-Space in
# the ROOT table to switch INTO the prefix table. @livepicker-key is therefore a
# PREFIX-table binding. `tmux bind-key` with NO `-T` and NO `-n` targets the prefix
# table by default (verified live on 3.6b). Do NOT add `-n` (root) — it would
# shadow tubular's root C-Space binding and break prefix entry for the whole session.
#
# DEPENDENCY: sources scripts/options.sh (P1.M1.T1.S1) for get_opt. The bind TARGET
# scripts/livepicker.sh is created by P1.M4.T1.S1 and NEED NOT EXIST YET —
# bind-key stores the path as a string; tmux only runs it when the key is pressed.
#
# GUARD (PRD §11): if @livepicker-key is unset/empty, print a display-message and
# bind nothing, exiting 0 so the plugin still loads cleanly.
#
# NO `set -e` — a bad @livepicker-key makes `tmux bind-key` print `unknown key:`
# and return non-zero; we want graceful degradation (warn + clean exit), not abort.
# `set -u` is inherited from options.sh and is safe here (every var is assigned first).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/options.sh
source "$CURRENT_DIR/scripts/options.sh"

KEY="$(get_opt "@livepicker-key" '')"

if [ -z "$KEY" ]; then
	# Unset/empty: do not bind. Tell the user how to enable, and load cleanly.
	tmux display-message 'tmux-livepicker: set @livepicker-key to activate'
	exit 0
fi

# Prefix-table bind (DEFAULT target — NO -n, NO -T). -n would put this in the root
# table and shadow tubular's root C-Space (switch-client -T prefix), breaking prefix.
tmux bind-key "$KEY" run-shell "$CURRENT_DIR/scripts/livepicker.sh"

exit 0
```

NOTE for the implementer: the block above is the COMPLETE, ready file body. Use it
as-is; the only allowed deviation is comment phrasing. Do NOT add `-T prefix`
(equivalent to default but the contract and session_history.tmux omit it). Do NOT
add `-n`. Do NOT add `set -e`. Do NOT create scripts/livepicker.sh (P1.M4's job).
Do NOT put the file in scripts/ (PRD §12 puts plugin.tmux at the repo ROOT).

### Integration Points

```yaml
LOADING (how plugin.tmux gets invoked — system_context §1, sibling_plugins §2):
  - Option A (tmux-thumbs style, recommended): add to ~/.config/tmux/tmux.conf,
    BEFORE the TPM init line:
        run-shell '~/.config/tmux/plugins/tmux-livepicker/plugin.tmux'
  - Option B (TPM autoload): add to the TPM @plugin block:
        set -g @plugin '<user>/tmux-livepicker'
    (TPM then runs plugin.tmux automatically.) Either works; run-shell avoids a
    TPM install step. NOT this task's job to edit tmux.conf — the implementer/user
    does that at install time (documented in README P1.M8.T1.S1). plugin.tmux just
    has to be executable + correct so either loader works.

DEPENDENCY (consumed):
  - scripts/options.sh (P1.M1.T1.S1 — COMPLETE): provides get_opt. Sourced at
    line ~25. plugin.tmux assumes $CURRENT_DIR/scripts/options.sh exists.

BIND TARGET (produced later, NOT this task):
  - scripts/livepicker.sh (P1.M4.T1.S1 — FUTURE): the activate script. Bound as a
    STRING path today; executed only on key press. Creating a stub here would
    collide with P1.M4's deliverable — do NOT create it.

STATE / CONFIG / DATABASE / MIGRATIONS / ROUTES: none. plugin.tmux is a pure
  entry point: one option read, zero or one bind, zero or one display-message.
  It does NOT touch @livepicker-* state (that is state.sh's domain), does NOT
  set hooks (session-history owns its hooks; livepicker's hook suppression is
  P1.M4.T4.S2), does NOT install status (P1.M4.T3.S1).
```

## Validation Loop

### Level 1: Syntax & Style (Immediate Feedback)

```bash
# Run after creating + chmod +x the file — fix before proceeding.
bash -n plugin.tmux                        # syntax check; expect no output, exit 0
shellcheck plugin.tmux                     # lint; expect 0 findings
# Tabs-not-spaces sanity (shfmt NOT installed):
grep -Pn '^    ' plugin.tmux && echo "FAIL: 4-space indent found, use tabs" || echo "OK: tabs only"
# Executable bit (REQUIRED — run-shell loading model):
[ -x plugin.tmux ] && echo "OK: executable" || { echo "FAIL: not executable"; chmod +x plugin.tmux; }

# Expected: all clean. shellcheck must NOT emit SC1090/SC2154 for get_opt — the
# `# shellcheck source=scripts/options.sh` directive on the source line resolves it.
# If shellcheck cannot find options.sh, run from the repo root (it resolves relative
# to plugin.tmux's dir): `cd <repo-root> && shellcheck plugin.tmux`.
```

### Level 2: Mock Validation — BOTH branches, zero live-server impact

The P1.M7 socket-isolation shim does not exist yet. We validate with a **fake
`tmux` on PATH** that logs invocations and serves a configurable `@livepicker-key`.
This touches NO live tmux state (it would otherwise clobber the user's live
`prefix Space → next-layout`). Run from the repo root, then delete the throwaway.

```bash
# Throwaway mock validation (do NOT commit a tests/ dir):
REPO_ROOT="$(pwd)"
MOCK_DIR="$(mktemp -d)"
LOG="$MOCK_DIR/tmux-calls.log"
: > "$LOG"

# Fake tmux: logs every call; answers the option read plugin.tmux (via options.sh)
# performs. $MOCK_KEY controls which branch is exercised.
cat > "$MOCK_DIR/tmux" <<'EOF'
#!/usr/bin/env bash
# fake tmux for plugin.tmux validation
echo "tmux $*" >> "$MOCK_LOG"
# options.sh::get_opt does: tmux show-option -gqv "@livepicker-key"
if [ "$1" = "show-option" ] && [ "$2" = "-gqv" ] && [ "$3" = "@livepicker-key" ]; then
    printf '%s\n' "${MOCK_KEY:-}"
fi
exit 0
EOF
chmod +x "$MOCK_DIR/tmux"

pass=0; fail=0
assert() { # $1 desc $2 actual-cond(0/1)
    if [ "$2" = "0" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL %s\n' "$1"; fi
}

# ---------- BRANCH 1: @livepicker-key = Space (the bind path) ----------
export MOCK_KEY="Space"
: > "$LOG"
PATH="$MOCK_DIR:$PATH" bash "$REPO_ROOT/plugin.tmux"; rc=$?
# rc should be 0 (trailing exit 0)
assert "branch1 exit code 0" "$([ "$rc" = "0" ] && echo 0 || echo 1)"
# exactly ONE bind-key call
binds=$(grep -c '^tmux bind-key' "$LOG")
assert "branch1 exactly 1 bind-key (got $binds)" "$([ "$binds" = "1" ] && echo 0 || echo 1)"
# the bind-key line must NOT contain -n or -T (prefix table is the default)
bad=$(grep '^tmux bind-key' "$LOG" | grep -cE '\s-n\s|\s-T\s')
assert "branch1 bind has NO -n/-T token" "$([ "$bad" = "0" ] && echo 0 || echo 1)"
# the bind-key line must reference the livepicker.sh target with the resolved CURRENT_DIR
tgt=$(grep '^tmux bind-key' "$LOG" | grep -cF "run-shell $REPO_ROOT/scripts/livepicker.sh")
assert "branch1 bind target is scripts/livepicker.sh (resolved)" "$([ "$tgt" = "1" ] && echo 0 || echo 1)"
# the bound key is Space
sp=$(grep '^tmux bind-key' "$LOG" | grep -cE '^tmux bind-key Space run-shell')
assert "branch1 bound key is Space" "$([ "$sp" = "1" ] && echo 0 || echo 1)"
# ZERO display-message calls on the bind path
dm=$(grep -c '^tmux display-message' "$LOG")
assert "branch1 zero display-message (got $dm)" "$([ "$dm" = "0" ] && echo 0 || echo 1)"

# ---------- BRANCH 2: @livepicker-key unset (the guard path) ----------
export MOCK_KEY=""
: > "$LOG"
PATH="$MOCK_DIR:$PATH" bash "$REPO_ROOT/plugin.tmux"; rc=$?
assert "branch2 exit code 0" "$([ "$rc" = "0" ] && echo 0 || echo 1)"
# ZERO bind-key calls
binds=$(grep -c '^tmux bind-key' "$LOG")
assert "branch2 zero bind-key (got $binds)" "$([ "$binds" = "0" ] && echo 0 || echo 1)"
# exactly ONE display-message with the byte-exact guard text
dm=$(grep -c "^tmux display-message 'tmux-livepicker: set @livepicker-key to activate'" "$LOG")
assert "branch2 one display-message (byte-exact text)" "$([ "$dm" = "1" ] && echo 0 || echo 1)"

printf 'PASS=%d FAIL=%d\n' "$pass" "$fail"
rm -rf "$MOCK_DIR"
[ "$fail" = "0" ]
# Expected: PASS=9 FAIL=0, exit 0. The "-n/-T token absent" assertion is the
# FINDING-1/FINDING-3 proof (prefix table by default; no root shadow). The
# byte-exact display-message assertion is the PRD §11 guard proof.
```

### Level 3: Integration Testing (System Validation)

```bash
# Live default-table confirmation (already done in research FINDING 1; re-runnable,
# self-cleaning, uses a harmless throwaway key '0' NOT 'Space' to avoid clobbering
# the user's live prefix Space → next-layout):
tmux bind-key 0 run-shell "/tmp/lp-default-table-probe"
tmux list-keys -T prefix | grep -F '/tmp/lp-default-table-probe' \
  && echo "OK: default-table bind lands in PREFIX" \
  || echo "FAIL: not in prefix table"
tmux list-keys -T root | grep -F '/tmp/lp-default-table-probe' \
  && echo "FAIL: should NOT be in root" \
  || echo "OK: not in root (no -n semantics confirmed)"
tmux unbind-key -T prefix 0 2>/dev/null
rm -f /tmp/lp-default-table-probe
# Expected: "OK: default-table bind lands in PREFIX" + "OK: not in root".

# Real-load smoke (OPTIONAL — only if you choose to wire plugin.tmux into tmux.conf
# for a manual UX check; NOT required for this subtask's sign-off, and it WILL
# overwrite prefix Space → next-layout until the key is pressed):
#   1. Ensure scripts/options.sh exists (it does — P1.M1.T1.S1 complete).
#   2. tmux source-file ~/.config/tmux/tmux.conf  (or prefix C-r) after adding the
#      run-shell line from Integration Points.
#   3. tmux list-keys -T prefix | grep Space   → shows the livepicker run-shell bind.
#   4. Press C-Space then Space → tmux tries to run scripts/livepicker.sh (which
#      does not exist yet → harmless "can't read .../livepicker.sh" error in the
#      status line; this proves the BIND is correct and the target is the right path).
# Defer the full UX smoke to P1.M4.T1.S1 (when livepicker.sh exists).
```

### Level 4: Creative & Domain-Specific Validation

```bash
# Reload-safety / idempotency: re-running plugin.tmux must not stack bindings or
# error. The mock run already re-runs it twice (branch1 then branch2) with no
# accumulation issue (each run is an independent process). For a live idempotency
# proof (harmless key '0', self-cleaning):
tmux bind-key 0 run-shell "/tmp/idem-1"
tmux bind-key 0 run-shell "/tmp/idem-2"      # re-bind same key → overwrites
n=$(tmux list-keys -T prefix | grep -cE 'run-shell /tmp/idem-[12]')
[ "$n" = "1" ] && echo "OK: re-bind overwrites (idempotent)" || echo "FAIL: stacked $n"
tmux list-keys -T prefix | grep -F '/tmp/idem-2' >/dev/null && echo "OK: latest wins" || echo "FAIL"
tmux unbind-key -T prefix 0 2>/dev/null
# Expected: both OK. Confirms plugin.tmux can be re-sourced on tmux.conf reload
# without stacking (mirrors session_history.tmux reload-safety).

# Invalid-key graceful degradation: a bogus @livepicker-key must NOT abort load.
MOCK_DIR="$(mktemp -d)"; LOG="$MOCK_DIR/log"; : > "$LOG"
cat > "$MOCK_DIR/tmux" <<EOF
#!/usr/bin/env bash
echo "tmux \$*" >> "$LOG"
if [ "\$1" = "show-option" ] && [ "\$2" = "-gqv" ] && [ "\$3" = "@livepicker-key" ]; then
    printf 'BogusKeyName\n'
fi
# simulate tmux rejecting the key
if [ "\$1" = "bind-key" ]; then echo "unknown key: BogusKeyName" >&2; exit 1; fi
exit 0
EOF
chmod +x "$MOCK_DIR/tmux"
PATH="$MOCK_DIR:$PATH" bash ./plugin.tmux; rc=$?
[ "$rc" = "0" ] && echo "OK: invalid key → script still exits 0 (graceful)" || echo "FAIL: rc=$rc"
rm -rf "$MOCK_DIR"
# Expected: OK (the trailing `exit 0` guarantees clean load despite the bind warning;
# no `set -e` means the failing bind-key did not abort). This is the contract's
# "Do NOT set -e (tmux bind may warn)" proof.
```

## Final Validation Checklist

### Technical Validation

- [ ] `bash -n plugin.tmux` exits 0 with no output.
- [ ] `shellcheck plugin.tmux` reports 0 findings (the `# shellcheck source=` directive
      resolves `get_opt`; no SC1090/SC2154).
- [ ] No 4-space indents (`grep -Pn '^    '` is empty); tabs only.
- [ ] `plugin.tmux` is executable (`-rwxr-xr-x`).

### Feature Validation

- [ ] File is at the REPO ROOT (`./plugin.tmux`), NOT in `scripts/`.
- [ ] Shebang `#!/usr/bin/env bash`; header documents the prefix-table rule + dependency.
- [ ] `CURRENT_DIR` computed via the canonical idiom; `scripts/options.sh` sourced.
- [ ] `KEY="$(get_opt "@livepicker-key" '')"` — empty default visible (the guard).
- [ ] Empty-key branch: `tmux display-message 'tmux-livepicker: set @livepicker-key to activate'`
      (byte-exact) + `exit 0`; ZERO bind-key calls.
- [ ] Bind branch: `tmux bind-key "$KEY" run-shell "$CURRENT_DIR/scripts/livepicker.sh"`
      with NO `-n` and NO `-T`; trailing `exit 0`.
- [ ] Mock validation: PASS=9 FAIL=0 across both branches (including the
      "no -n/-T token" and "byte-exact display-message" proofs).
- [ ] Live default-table probe (key '0', self-cleaning) lands in `-T prefix`, not root.
- [ ] No `scripts/livepicker.sh` created by this task (it is P1.M4.T1.S1's deliverable).

### Code Quality Validation

- [ ] NO `set -e` anywhere (contract: "tmux bind may warn").
- [ ] NO explicit `set -u` (inherited from options.sh; redundant to add).
- [ ] All expansions double-quoted (`"$KEY"`, `"$CURRENT_DIR/..."`).
- [ ] Structure mirrors session_history.tmux (flat top-level, CURRENT_DIR, inline
      option read, option-driven bind-key, reload-safe).
- [ ] `# shellcheck source=scripts/options.sh` directive on the source line.
- [ ] Indent with tabs.

### Documentation & Deployment

- [ ] Header comment states: entry point purpose, the prefix-table-vs-root rule
      (no -n; -n shadows tubular's C-Space), the options.sh dependency, the
      unset-guard, and that the bind target livepicker.sh is created by P1.M4.
- [ ] No README/doc file created (DOCS = Mode A; install/usage covered by README
      P1.M8.T1.S1). No tmux.conf edit performed by this task (the user/implementer
      wires the run-shell line at install time).
- [ ] No new env vars introduced; no @livepicker-* state touched.

---

## Anti-Patterns to Avoid

- ❌ Don't add `-n` to the `bind-key` — it targets the ROOT table and SHADOWS
  tubular's root `C-Space` binding (`switch-client -T prefix`), breaking prefix
  entry for the whole session. The default (no `-T`/`-n`) is the prefix table
  (research FINDING 1, live-proven).
- ❌ Don't add `-T root` for the same reason. `-T prefix` is equivalent to the
  default but unnecessary; omit it to match the contract + session_history.tmux.
- ❌ Don't put plugin.tmux in `scripts/` — PRD §12 file layout places it at the
  REPO ROOT (it is the entry point TPM/tmux invokes by name).
- ❌ Don't forget `chmod +x` — the `run-shell` loading model executes the file via
  its shebang; a non-executable file fails "Permission denied" (research FINDING 5;
  session_history.tmux is `-rwxr-xr-x`).
- ❌ Don't add `set -e` — an invalid `@livepicker-key` makes `tmux bind-key` print
  `unknown key:` and return non-zero; `set -e` would abort plugin load. The
  contract explicitly forbids it ("tmux bind may warn"). Graceful degradation via
  no-`set -e` + trailing `exit 0` is the intent.
- ❌ Don't create `scripts/livepicker.sh` (even a stub) — it is P1.M4.T1.S1's
  deliverable. `bind-key ... run-shell "<path>"` stores the path as a string; the
  target need not exist until the key is pressed.
- ❌ Don't use `opt_key` instead of the inline `get_opt "@livepicker-key" ''` —
  the contract specifies the inline form, and the visible `''` documents the guard
  semantic at the call site (research FINDING 9). (`opt_key` is equivalent and
  fine for downstream scripts, but plugin.tmux is the one place the empty default
  should be visible.)
- ❌ Don't add a `tmux_is_set` probe to decide the guard — `get_opt`'s empty-default
  already covers both "unset" and "set-to-empty"; the `-z` test is sufficient and
  correct. An `is_set` probe would re-introduce the useless-probe problem
  (utils FINDING 2) in a place it isn't needed.
- ❌ Don't try to "preserve" tmux's default `prefix Space → next-layout` — binding
  `Space` is SUPPOSED to overwrite it (the user set `@livepicker-key Space`
  deliberately). "Preserving" next-layout would defeat the binding (research FINDING 2).
- ❌ Don't create a `tests/` directory or committed test file — the harness is
  invented in P1.M7.T1/T2. Validate via the throwaway mock (Validation §2) and
  delete it.
- ❌ Don't edit `~/.config/tmux/tmux.conf` in this task — wiring the `run-shell`
  line is an install-time/user action documented in README P1.M8.T1.S1. plugin.tmux
  only has to be correct + executable so either loader (run-shell or TPM) works.
- ❌ Don't use 4-space indent — tabs only (system_context §9).

---

## Confidence Score

**9 / 10** for one-pass success. Rationale: the deliverable is a ~20-line entry
point whose body is given verbatim above, structurally a strict subset of the
named template (`session_history.tmux`, read in full). The single highest-
consequence decision — prefix table via default `bind-key` (no `-n`/`-T`) — is
backed by a LIVE proof (`bind-key 0 run-shell /tmp/...` → `list-keys -T prefix`,
cleaned up) plus the documented tubular root-C-Space reality. Both branches
(set-key bind; empty-key guard) are exercised by a zero-impact mock that asserts
the exact emitted command string AND the absence of `-n`/`-T` tokens. The input
dependency (`scripts/options.sh`, P1.M1.T1.S1) is complete and its `get_opt`
signature is fixed. The bind target (`scripts/livepicker.sh`, P1.M4.T1.S1) does
not need to exist (bind-key stores a path string). Tools verified present:
`tmux 3.6b`, `bash 5.x`, `shellcheck`. Residual risk: (a) shellcheck needing the
`source` directive to resolve `get_opt` (handled by the directive; caught at
Level 1); (b) the implementer mistakenly placing the file in `scripts/` or
omitting `chmod +x` (both called out as hard requirements + anti-patterns +
checklist items). All residual risks are deterministically caught by the
validation loop.
