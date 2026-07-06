# README.md findings — P1.M8.T1.S1

Source: live read of repo + `plan/001_fd5d622d3939/architecture/{system_context,sibling_plugins_and_env}.md`
+ sibling READMEs. All facts verified against the SHIPPED code on 2026-07-06.

## FINDING 1 — This is the Mode B catch-all (runs LAST)
`<item_description>` §1: it depends on EVERY implementing subtask, so it must reflect
SHIPPED behavior, not PRD aspirations. The plugin (P1.M1–M6) is COMPLETE; tests P1.M7.T1–T5
are COMPLETE; P1.M7.T6.S1 (test_restore/keyrepurpose/create) is being implemented IN PARALLEL.
=> The README's "Validation" section must describe `bash tests/run.sh` generically (the
PRD §15 clusters it covers), NOT a hard test count (in flux). List the test FILES.

## FINDING 2 — Sibling README convention (the style contract)
`<item_description>` §1 names session-history/sessionx as "concise (what/install/options/usage)".
Read both. **session-history** is the closest sibling (architecture §1 says livepicker composes
most tightly with it) and the cleanest template:
  Title + tagline → Why → Features → Install (TPM + manual run-shell) → Keys table →
  Options table → How it works → Requirements (version floor) → Limitations → License.
sessionx is more elaborate (Nix, prerequisites, screenshots) — DO NOT mimic its verbosity.
The work item lists the EXACT required sections (Overview, Goals/non-goals, User stories,
Install, Config, Usage, How it works, Compatibility, Validation) — follow THAT order.

## FINDING 3 — Installation: TWO load paths (both real precedents)
architecture system_context §2 + sibling_plugins §2:
  (a) TPM autoload: `set -g @plugin '<org>/tmux-livepicker'` (then `run '~/.tmux/plugins/tpm/tpm'`).
  (b) Manual run-shell: `run-shell '~/.config/tmux/plugins/tmux-livepicker/plugin.tmux'`
      — mirrors tmux-thumbs (tmux.conf:128 `run-shell '~/.config/tmux/plugins/tmux-thumbs/tmux-thumbs.tmux'`).
plugin.tmux IS the entry point: `tmux bind-key "$KEY" run-shell "$CURRENT_DIR/scripts/livepicker.sh"`.
CRITICAL: `@livepicker-key` is REQUIRED — if unset, plugin.tmux prints `display-message` and binds
nothing (clean exit). The user's tmux.conf:121 already pre-declares `set -g @livepicker-key 'Space'`
(a PREFIX-table key — press C-Space → prefix table → Space). Document that the user MUST set it.

## FINDING 4 — Config table: ship verbatim from PRD §11 + options.sh
options.sh defines `opt_<name>()` accessors with EXACT PRD §11 defaults (verified 1:1):
  key=""(required), type=session, create=on, next-key=C-M-Tab, prev-key=C-M-BTab,
  nav-next-keys="Down j", nav-prev-keys="Up k", confirm-keys=Enter, cancel-keys=Escape,
  backspace-keys=BSpace, preview-mode=live, suppress-window-hook=on, fg=default, bg=default,
  highlight-fg=black, highlight-bg=yellow, show-count=on, status-format-index=0.
Reproduce the full table. These are the ONLY public options (`@livepicker-` prefix).

## FINDING 5 — Compatibility floor: 3.2 (multi-line status), tested 3.6b
architecture system_context §10: "The genuinely binding feature is multi-line status/status-
format[n], likely introduced in 3.2 ... Recommend documenting the floor as 3.2 and ... test on
the installed 3.6b." The item_description §1 confirms: "document 3.2 (multi-line status) as the
minimum, note 3.6b is the tested target". Do NOT say 3.0 (PRD's guess). Composes with:
tmux-session-history (the invariant we protect), tmux-sessionx, tmux-resurrect, tubular
(PRD §14 / architecture §10).

## FINDING 6 — Usage flow + the prefix-table key subtlety
activate: prefix (@livepicker-key) → status grows to 2 lines, line 1 = picker, area below = live
preview of highlighted session. Filter by typing. Navigate with C-M-Tab/C-M-BTab (repurposed
window-nav) + Down/j, Up/k. Confirm=Enter (creates session from query if no match + create on),
cancel=Escape (clears query first, then cancels). NOTE the prefix-table nuance (architecture §5/§8):
prefix is None, tubular binds C-Space in ROOT to enter the prefix table. So @livepicker-key Space
means: C-Space → prefix table → Space. Mention this so users understand why a plain keypress.

## FINDING 7 — How it works: the ONE invariant (PRD §4 + §7)
The single load-bearing sentence: browsing links the candidate's active window into the current
session via `tmux link-window` and selects it (`select-window`) — it does NOT `switch-client`.
`select-window` fires `session-window-changed` (suppressed by default) but NOT `client-session-
changed`, so the session-history timeline + toggle are untouched. The ONLY session switch is the
single `switch-client` at confirm. One paragraph.

## FINDING 8 — Validation: `bash tests/run.sh`
tests/run.sh: sources setup_socket.sh + helpers.sh + every tests/test_*.sh, discovers test_*
functions, runs each against a FRESH isolated socket (PATH-wrapper shim — invented, no sibling
has it), prints PASS/FAIL + summary, exits 0 iff all pass. The suites cover PRD §15 clusters:
functional (test_functional.sh), live all-panes preview (test_preview.sh), pollution invariant
(test_pollution.sh), restore (test_restore.sh — T6), key-repurpose (test_keyrepurpose.sh — T6),
create-on-enter (test_create.sh — T6). The shim guarantees the user's REAL tmux server is untouched.

## FINDING 9 — PRD §0 removal is a RECOMMENDATION (do NOT edit PRD.md)
item_description §1: "Do NOT modify PRD.md (read-only per SOW); PRD §0 'Prior attempt' removal is a
human post-verification decision — note it as a recommendation in README or a CHANGELOG." CHANGELOG
is owned by sibling task P1.M8.T1.S2. So the README adds a short "Maintenance" note recommending
§0 removal after verification; it does NOT touch PRD.md. This keeps S1/S2 non-conflicting.

## FINDING 10 — Scope boundary (no conflicts)
ONLY file produced: `README.md` at repo root. Do NOT touch PRD.md, tasks.json, prd_snapshot.md,
.gitignore, any scripts/* or tests/* (all COMPLETE/IMMUTABLE), or create CHANGELOG (S2 owns it).
No LICENSE exists yet; reference one only as a "add a LICENSE if distributing" note (do not create it).
