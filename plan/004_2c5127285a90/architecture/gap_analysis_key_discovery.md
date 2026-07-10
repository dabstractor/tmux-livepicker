# Gap Analysis: Key Discovery (PRD §8) vs Current Implementation

## Current state

The implementation has **NO key discovery**. `livepicker.sh:355-357` explicitly states:
"Discovery (PRD §8) is intentionally OMITTED: the defaults (C-M-Tab / C-M-BTab)
already match this user's root-table window-nav keys."

Hardcoded defaults in `options.sh:30-33`:
- `opt_next_key` = `C-M-Tab` (single key, session nav)
- `opt_prev_key` = `C-M-BTab` (single key, session nav)
- `opt_nav_next_keys` = `Down` (space-list, session nav)
- `opt_nav_prev_keys` = `Up` (space-list, session nav)

## PRD §8 Discovery algorithm

For each axis, if the user has NOT set the corresponding `@livepicker-*-keys` option:
scan `tmux list-keys -T root` AND `-T prefix`.

- **Window axis next**: command contains `select-window -n`, `select-window -t +1`,
  `select-window -t :+1`, `next-window` (incl `-a`), or the `swapwindow … \;
  select-window -t +1` compound. **prev**: symmetric.
- **Session axis next**: command is `switch-client -n`. **prev**: `switch-client -p`.
  NOT `-l` or `-t`. Always add `Down`/`Up` as extras.

Post-processing: drop plain `a-z`/`A-Z`/`0-9`, de-duplicate, exclude fixed control
keys.

## Mouse key exclusion (critical)

The live root table contains mouse bindings whose lines contain `switch-client -n`,
`next-window`, etc. INSIDE `display-menu` blocks:
- `WheelDownStatus` → `next-window`
- `WheelUpStatus` → `previous-window`
- `MouseDown3StatusLeft` → `display-menu … { switch-client -n } …`
- `MouseDown1Status` → `switch-client -t =`

Discovery MUST: (a) match only the top-level command token (not substrings inside
display-menu), (b) exclude keys matching `Mouse*`/`Wheel*`.

## Expected discovery output (verified on live 3.6b)

- Window next: `C-M-Tab M-n C-n C-l`
- Window prev: `C-M-BTab M-p C-p C-h`
- Session next: `) Down`
- Session prev: `( Up`

## lp_filter_harmful_bindings (utils.sh:102-131)

A stdin→stdout `grep -vE` filter that drops switching/mutating commands from the
copied key table. It drops `switch-client`, `next-window`, `previous-window`,
`select-window`, `swap-window`, etc. from the COPY. Discovery reads the RAW
`list-keys` BEFORE this filter is applied — the filter and discovery are
complementary: the filter removes nav keys from the pass-through copy; discovery
re-binds them explicitly as picker actions.

## Option model change

| Current | PRD | Notes |
|---------|-----|-------|
| `@livepicker-next-key` (single, C-M-Tab) | `@livepicker-window-next-keys` (list, discovered) | Window axis |
| `@livepicker-prev-key` (single, C-M-BTab) | `@livepicker-window-prev-keys` (list, discovered) | Window axis |
| `@livepicker-nav-next-keys` (list, Down) | `@livepicker-session-next-keys` (list, discovered) | Session axis |
| `@livepicker-nav-prev-keys` (list, Up) | `@livepicker-session-prev-keys` (list, discovered) | Session axis |
