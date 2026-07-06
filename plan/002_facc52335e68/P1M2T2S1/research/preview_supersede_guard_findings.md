# Research — P1.M2.T2.S1: `expected_seq` arg + supersede guard in preview.sh (PRD §18)

> All findings below were verified LIVE against a fresh isolated tmux socket via
> `tests/setup_socket.sh` (the repo's own PATH-shim harness) on tmux 3.6b, against
> the CURRENT working tree (which has the §17 tab-style work + the 001-bugfix
> window-index resolution already landed). `STATE_PREVIEW_SEQ` is NOT yet a
> constant (P1.M2.T1.S1 is in-flight) — its `@livepicker-preview-seq` option NAME
> is known from that PRP, so the guard LOGIC was verified against the raw option.

---

## FINDING 1 — exact CURRENT structure of preview_main() (anchor every edit on CONTENT)

**Live-verified** (`grep -n` on the working tree). The task contract's line numbers
are ~1 line drifted from `codebase_state.md §5`; anchor on CONTENT, not line numbers.

```
74  preview_main() {
75    local S="${1:-}"                                   # <- Task 1: add expected_seq="${2:-}"
76    local current_session orig_window linked_id src_id w_sess w_idx   # <- Task 1: add expected_seq here, + cur_seq
77    (blank)
78-84   # cheap reads: current_session / orig_window / linked_id   # <- PRIMARY GUARD goes BEFORE these (Task 2)
85-88   # @livepicker-preview-mode gate (off->return; snapshot->fallback; live->fall through)
101-113 # self-session guard (unlink + unset LINKED_ID + select ORIG_WINDOW) — MUTATES
119-131 # src_id resolution (window-index awk | session active-filter)
137-142 # duplicate guard (linked_id==src_id -> just select; MUTATES select)
145-149 # unlink-previous (if linked_id: unlink-window) — MUTATES         # <- Task 3: re-read linked_id BEFORE this
153-158 # link-window -a (guarded fallback) — MUTATES
161     # select-window -t "$src_id" — MUTATES                           # <- Task 4: optional 2nd guard
164     # set_state "$STATE_LINKED_ID" "$src_id"
166   }
168   preview_main "$@" || exit 1
```

**The two existing locals at lines 75-76 are the anchor for Task 1.** The mode-gate
(line 85) is the anchor for "the guard goes ABOVE this". The unlink-previous block
(lines 145-149) is the anchor for Task 3 (re-read linked_id).

---

## FINDING 2 — the supersede-guard LOGIC is correct (all 4 cases live-verified)

Tested the exact guard condition `[ "$cur_seq" != "$expected_seq" ] && return 0`
(gated by `if [ -n "$expected_seq" ]`) against the isolated socket, simulating
`@livepicker-preview-seq`:

| case | expected_seq | live seq | result | correct? |
|------|--------------|----------|--------|----------|
| A (sync, one-arg) | `""` | (any) | guard SKIPPED → mutate | ✓ (synchronous path unchanged) |
| B (current) | `"3"` | `"3"` | CURRENT → mutate | ✓ |
| C (stale) | `"3"` | `"5"` | STALE → no-op | ✓ (newer target won) |
| D (teardown) | `"3"` | unset→`"0"` | STALE → no-op | ✓ (late post-teardown job can't clobber) |

Case D is the load-bearing one: `clear_all_state` (P1.M2.T1.S1 puts
`STATE_PREVIEW_SEQ` in `_STATE_RUNTIME_KEYS`) unsets the seq on exit → `get_state
"$STATE_PREVIEW_SEQ" "0"` returns `"0"` ≠ the captured seq → late job no-ops. This
is the Q6 teardown-safety guarantee, confirmed live.

`get_state` with default `"0"` returns `"0"` when the option is unset (verified:
`tmux_get_opt` does `v=$(show-option -gqv); [ -n "$v" ] && echo "$v" || echo "${2:-}"`).

---

## FINDING 3 — the PRIMARY guard belongs at the TOP (before the mode-gate), and this is SAFER than Q6's literal reference

The task contract places the primary guard **before the preview-mode gate (line 85)** —
i.e., at the very top, before the cheap reads AND before the self-session guard.

Q6's reference impl places the gate "immediately before any unlink/link/select"
(i.e., AFTER the cheap reads). But the **self-session guard (lines 101-113) MUTATES**
(`unlink-window` + `tmux_unset_opt STATE_LINKED_ID` + `select-window`). Q6's
"after the cheap reads" placement would let a stale job REACH the self-session
guard and mutate. The contract's **TOP placement bails a stale job before ALL
mutations**, including the self-session guard's. **The contract's placement is
correct and strictly safer.** Follow the contract: guard at the top.

A stale job at the top does ZERO work (not even the cheap reads) — most efficient.

---

## FINDING 4 — re-read `linked_id` right BEFORE the unlink block (race-narrowing)

The contract: re-read `linked_id` immediately before the `if [ -n "$linked_id" ]`
unlink block (lines 145-149), not just once at the top (line 84).

**Why:** the top read (line 84) is a snapshot at job entry. Between entry and the
unlink, a newer `-b` job may have linked a DIFFERENT window and set `linked_id` to
its `@id`. Re-reading ensures the unlink targets the window that is **actually linked
in the driver NOW** (the freshest), clearing the real preview slot — rather than a
stale `@id` that may already be gone (harmless `|| true` but leaves the real slot
occupied, risking a duplicate on the subsequent `link-window -a`).

`local linked_id` is already declared at line 76 — reassigning it (`linked_id="$(get_state …)"`)
is fine (no new `local` needed; it just overwrites the existing local).

---

## FINDING 5 — the OPTIONAL second guard: place it BEFORE the unlink (first mutation), NOT "before the final select"

The contract says "optionally add a second seq re-check right before the final
select-window (~line 158)". Q6 says the same. **BUT placing it before the final
`select-window` (line 161) creates an untracked-link LEAK:**

- Execution order is: `link-window` (153) → [2nd guard here?] → `select-window` (161) → `set_state LINKED_ID` (164).
- If the 2nd guard fires (returns 0) between link and select, then `set_state` (164)
  is SKIPPED → the just-linked `src_id` window is linked in the driver but **NOT
  tracked** in `@livepicker-linked-id`. The next preview / restore unlinks the
  TRACKED id, leaving `src_id` stranded (a leak).

**Safer placement (recommended): put the 2nd guard immediately BEFORE the unlink
block (line 145), i.e., before the FIRST mutation.** A stale job then skips
unlink + link + select + set_state entirely — a TRUE no-op (no leak). This still
"close[s] the read→mutate race" (the contract's stated goal) — in fact MORE
aggressively, because it guards before the first mutation rather than the last.

Both the contract and Q6 mark the 2nd guard **optional**. Given the leak risk of
the literal placement, the PRP recommends the before-unlink placement and documents
the rationale. (If the implementer prefers the literal "before select", they must
also move `set_state` to immediately after `link-window` to avoid the leak — but
that is extra churn; the before-unlink placement is strictly simpler and safer.)

---

## FINDING 6 — `opt_preview_defer` is NOT needed in preview.sh (the guard keys on $2)

The guard condition is `if [ -n "$expected_seq" ]` — it keys on whether the CALLER
passed a 2nd arg, NOT on `opt_preview_defer()`. The synchronous-vs-deferred
distinction is made by the CALLER (P1.M2.T3.S1's fire helper): the deferred path
passes `$seq` as $2; the synchronous path (activation first-preview; preview-defer=off)
passes only the session token. So preview.sh does NOT need to read
`opt_preview_defer` or `STATE_PREVIEW_TARGET`. It only reads `STATE_PREVIEW_SEQ`
(the re-check). This keeps the change minimal.

---

## FINDING 7 — DISJOINT from the parallel P1.M2.T1.S1 (no file conflict)

P1.M2.T1.S1 edits: `options.sh`, `state.sh`, `livepicker.sh` (adds
`opt_preview_defer`, `STATE_PREVIEW_SEQ`/`STATE_PREVIEW_TARGET`, the seq-init).
This task edits: `scripts/preview.sh` ONLY. **No shared file → no edit collision.**

Runtime dependency: preview.sh sources state.sh (line 41) and options.sh (line 38).
Once P1.M2.T1.S1 lands, `STATE_PREVIEW_SEQ` is a defined constant in scope inside
preview_main. **Until then, `STATE_PREVIEW_SEQ` is undefined** → the implementer
must NOT run the full preview.sh smoke before P1.M2.T1.S1 lands (it would
`set -u`-fail on the unbound `STATE_PREVIEW_SEQ`). Validation strategy: either
(a) land P1.M2.T1.S1 first (it's the dependency), or (b) validate the guard LOGIC
via the standalone snippet (FINDING 2) that uses the raw `@livepicker-preview-seq`
option name. The PRP's L2 smoke assumes P1.M2.T1.S1 has landed (normal ordering).

---

## FINDING 8 — NO committed test in this subtask (feature tests are P1.M3.T1)

The plan separates implementation (M2) from validation tests (M3). P1.M3.T1.S1
writes `tests/test_responsiveness.sh` (§15.23 deferred-preview validation), which
exercises the end-to-end deferred behavior. This subtask validates via **throwaway
smokes** (L2/L3) that are deleted after — exactly the discipline P1.M2.T1.S1 used
("Don't commit a tests/ file for this subtask — feature tests are P1.M3.T1").
The throwaway smoke proves: one-arg path unchanged; two-arg current-seq mutates;
two-arg stale-seq no-ops.

---

## FINDING 9 — preview.sh is CLIENT-INDEPENDENT (smoke needs no attach_test_client)

preview.sh reads the driver from `@livepicker-orig-session` via `get_state` (NOT
`display-message`). So the smoke runs on the detached isolated socket without
`attach_test_client` (mirror `tests/test_preview.sh`'s `lp_preview_seed_state`).
Verified live: a bare `preview.sh alpha2` on the detached socket linked `@4` and
set `@livepicker-linked-id` correctly (FINDING 2 baseline).

---

## FINDING 10 — `set -u` safety: declare `expected_seq` + `cur_seq` as locals

preview.sh inherits `set -u`. Every new var must be declared `local` and assigned
before use:
- `expected_seq="${2:-}"` — assigned inline in the `local` line (empty when $2
  absent → `set -u`-safe; the `[ -n "$expected_seq" ]` gate handles empty).
- `cur_seq` — declare in the locals line (`local … cur_seq`); assigned only inside
  the `if [ -n "$expected_seq" ]` block where it is read. Declared-but-unassigned is
  `set -u`-safe as long as it is never READ before assignment (it isn't — the read is
  inside the same `if`). Verified pattern: matches preview.sh's existing
  `src_id`/`w_sess`/`w_idx` (declared in the locals line, assigned later).

---

## FINDING 11 — the entry point `preview_main "$@"` passes ALL args through (no change needed)

Line 168: `preview_main "$@" || exit 1`. `"$@"` forwards EVERY arg to preview_main,
so `$2` (the seq) is already plumbed through automatically. **No change to the entry
point is needed** — only the `local S="${1:-}" expected_seq="${2:-}"` inside
preview_main. Verified: `"$@"` expands to all positional params.

---

## FINDING 12 — STYLE: TABS; the file has file-wide `shellcheck disable=SC1091,SC2153`

preview.sh uses TABS (no space-indent; `grep -Pn '^    '` → no hits). The file-wide
`shellcheck disable=SC1091,SC2153` covers sourcing + the readonly-const references.
The new `STATE_PREVIEW_SEQ` reference inside preview_main is covered (it's a sourced
readonly const, same as `STATE_LINKED_ID`). No new shellcheck disable needed. The
`get_state "$STATE_PREVIEW_SEQ" "0"` call is clean (no SC2086 — single quoted args).
