# lp_discover_axis_keys — empirical grounding (tmux 3.6b, live user key tables)

> Verified LIVE on 2026-07-09 against the user's real tmux server (read-only
> `list-keys` — no mutation). The discovery algorithm was PROTOTYPED and run
> against the live tables; it produces the correct key SET for all 4 axes. This
> file records the parsing traps and the live bindings the algorithm must handle.

## Environment

| Tool | Version |
|---|---|
| tmux | **3.6b** |
| bash | **5.3.15(1)-release** |
| user locale | `en_US.UTF-8` |

## T1.S1 status: LANDED (the accessors this discovery feeds exist)

`scripts/options.sh:30-33` defines the 4 two-axis accessors with EMPTY defaults
(`opt_session_next_keys` / `_prev_` / `opt_window_next_keys` / `_prev_`), each
`get_opt "@livepicker-<suffix>" ""`. Empty ⇒ discover (this function). The 4 OLD
accessors (`opt_next_key` etc.) are removed. The downstream caller is
livepicker.sh T4 (reworked by P1.M2.T1.S1).

---

## FINDING 1 — The live nav-relevant bindings (the discovery input)

ROOT table (nav-relevant):
```
bind-key -T root MouseDown1Status       switch-client -t =                        # MOUSE — exclude (Mouse*)
bind-key -T root MouseDown3StatusLeft   display-menu … { switch-client -n } …     # MOUSE FALSE POSITIVE — exclude
bind-key -T root WheelUpStatus          previous-window                           # MOUSE — exclude (Wheel*)
bind-key -T root WheelDownStatus        next-window                               # MOUSE — exclude (Wheel*)
bind-key -T root M-n                    select-window -n                          # window/next ✓
bind-key -T root M-p                    select-window -p                          # window/prev ✓
bind-key -T root M-MouseDown3StatusLeft display-menu … { switch-client -n } …    # MOUSE FALSE POSITIVE — exclude
bind-key -T root C-Space                switch-client -T prefix \; refresh-client # session: -T (not -n/-p) — exclude
bind-key -T root C-M-Tab                swap-window -t +1 \; select-window -t +1  # window/next ✓ (compound)
bind-key -T root C-M-BTab               swap-window -t -1 \; select-window -t -1  # window/prev ✓ (compound)
```

PREFIX table (nav-relevant):
```
bind-key    -T prefix )        switch-client -n      # session/next ✓
bind-key    -T prefix (        switch-client -p      # session/prev ✓
bind-key    -T prefix 0..9     select-window -t :=N  # DIGITS — dropped (plain 0-9)
bind-key    -T prefix Z        switch-client -l      # session: -l (not -n/-p) — exclude
bind-key    -T prefix n        next-window           # window/next but 'n' plain — DROPPED
bind-key    -T prefix p        previous-window       # window/prev but 'p' plain — DROPPED
bind-key    -T prefix M-n      next-window -a        # window/next ✓
bind-key    -T prefix M-p      previous-window -a    # window/prev ✓
bind-key -r -T prefix C-h      select-window -p      # window/prev ✓ (NOTE the -r flag!)
bind-key -r -T prefix C-l      select-window -n      # window/next ✓ (NOTE the -r flag!)
bind-key    -T prefix C-n      next-window           # window/next ✓
bind-key    -T prefix C-p      previous-window       # window/prev ✓
```

---

## FINDING 2 — The parser (tokenize; the `-r` flag + alignment spaces shift positions)

The bind-key line format is `bind-key [-r] -T <table> <key> <command...>`. TWO
complications verified live:
1. **The `-r` flag is optional** and shifts the key/command position
   (`bind-key -r -T prefix C-h select-window -p`). Field-position parsing breaks.
2. **Alignment spaces vary**: root lines are `bind-key -T root …` but prefix lines
   are `bind-key    -T prefix …` (extra spaces). Fixed-column splits break.

**The robust parse (PROTOTYPED + verified):** word-split the line (`set -- $line`),
drop `bind-key`, skip every token until `-T`, drop `-T` and the table name, the next
token is the KEY, the rest (rejoined) is the COMMAND. This handles `-r` and
alignment uniformly.

**⚠️ TRAP (load-bearing):** `set -- $line` inside the function CLOBBERS the
function's positional parameters ($1/$2 = axis/dir). SAVE axis/dir to `local`
variables BEFORE the read-loop. (The prototype does this — it's why it works.)

---

## FINDING 3 — Mouse exclusion is ESSENTIAL (two complementary protections)

Mouse bindings contain nav commands that would be false positives:
- `WheelDownStatus → next-window` (TOP-LEVEL command — a substring match WOULD catch it)
- `MouseDown3StatusLeft → display-menu … { switch-client -n } …` (switch-client -n INSIDE a block)

**Protection 1 — exclude keys matching `Mouse*` / `Wheel*`** (a `case "$key" in
Mouse*|Wheel*) continue ;; esac` guard). This is REQUIRED for the window axis
(WheelDownStatus→next-window is top-level) and belt-braces for the session axis.

**Protection 2 — session axis uses EXACT top-level match** (not substring): the
command must BE `switch-client -n` or START WITH `switch-client -n ` (note the
trailing space — distinguishes `-n` from `-l`/`-t`). This means `display-menu …
{ switch-client -n }` does NOT match (it starts with `display-menu`), even if the
key weren't mouse-excluded. Verified: `Z → switch-client -l` and
`C-Space → switch-client -T prefix …` are correctly EXCLUDED (not -n/-p).

The window axis uses SUBSTRING match (so `swap-window -t +1 \; select-window -t +1`
matches via the `select-window -t +1` substring) — but relies on Protection 1 to
drop Wheel*/Mouse*.

---

## FINDING 4 — The plain-alphanumeric drop + de-dup (verified)

- `case "$key" in [A-Za-z0-9]) continue ;; esac` drops EXACTLY single-char
  alphanumerics: `n`, `p`, `0`-`9` are dropped; `)`, `(` (not in the class) are
  KEPT; multi-char `C-n`/`M-p`/`C-M-Tab` don't match the single-char glob. ✓
- De-dup (first-seen): `M-n` appears in BOTH root (`select-window -n`) and prefix
  (`next-window -a`); it appears ONCE in the output. The `case " $seen " in
  *" $key "*)` guard handles it. ✓

---

## FINDING 5 — Prototype output vs the contract's "expected" strings

The prototyped algorithm run against the live server:
```
window/next → [M-n C-M-Tab C-l C-n]   window/prev → [M-p C-M-BTab C-h C-p]
session/next → [) Down]               session/prev → [( Up]
```
Contract "expected": `C-M-Tab M-n C-n C-l` | `C-M-BTab M-p C-p C-h` | `) Down` | `( Up`.

**The SET matches exactly (verified order-independent for all 4 axes).** The ORDER
differs (e.g. `M-n C-M-Tab` vs `C-M-Tab M-n`) because:
1. list-keys output order is not contractually stable (it follows tmux's internal
   binding order, roughly insertion/sorted).
2. The contract's expected order is neither first-seen-from-listkeys nor alphabetical
   — it's a hand-written reference SET.

**Conclusion: ORDER IS FUNCTIONALLY IRRELEVANT.** The caller (activate T4) binds
each discovered key to the SAME action (next-window / prev-window / next-session /
prev-session). Since every discovered key is DISTINCT (de-duped), the binding order
among them doesn't matter (tmux keeps the last binding per key, but there are no
duplicate keys). **The validation must assert the SET (order-independent), not the
exact string.** Document this.

---

## FINDING 6 — Control-key exclusion via get_opt (the contract's chosen approach)

The exclude set = confirm/cancel/backspace/rename/delete keys, read via
`get_opt "@livepicker-<name>" "<default>"` (the contract's explicit guidance: "Use
get_opt with the option names directly since opt_* functions may not be defined when
utils.sh is sourced standalone"). get_opt is defined in options.sh, which activate
sources BEFORE calling this function — so it IS available at call time (bash resolves
function calls at call time, not source time). For THIS user the exclude set
{Enter, Escape, BSpace, C-r, M-BSpace} doesn't collide with any discovered key, but
the logic must run for users whose nav keys might collide. The validation smoke
sources options.sh alongside utils.sh (the real call environment).

---

## The verified algorithm (prototype, all 4 axes correct)

```
lp_discover_axis_keys AXIS DIR:
  save axis/dir to locals (set -- inside the loop clobbers $1/$2)
  combined = list-keys -T root ; list-keys -T prefix
  for each line:
    tokenize; skip to -T; skip table; key = next token; cmd = rest (rejoined)
    skip Mouse*/Wheel* keys
    classify (axis:dir):
      window:next  — cmd substring ∈ {select-window -n, select-window -t +1, select-window -t :+1, next-window}
      window:prev  — cmd substring ∈ {select-window -p, select-window -t -1, select-window -t :-1, previous-window}
      session:next — cmd == "switch-client -n"  OR  cmd starts with "switch-client -n "
      session:prev — cmd == "switch-client -p"  OR  cmd starts with "switch-client -p "
    skip non-matches
    drop single-char [A-Za-z0-9] keys
    skip keys in the get_opt exclude set (confirm/cancel/backspace/rename/delete)
    de-dup (first-seen); append to output
  session axis: append "Down" (next) / "Up" (prev)
  print space-joined output
```
