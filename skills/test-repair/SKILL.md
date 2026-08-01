---
name: test-repair
description: "Use this skill when the user asks to \"fix the broken test\", \"repair this spec\", \"the selector changed\", or wants a test fixed where the TEST is at fault and the application is not. Fires only on failures /test-triage classified as test-bug. May fix selectors, waits, setup and teardown — may never weaken or delete an assertion, add a sleep, raise a retry, or add a skip. Anything touching an assertion escalates to human review instead of appearing in the diff. Proposes a diff; never commits, never merges. Works in any git repo; nothing here is project-specific."
version: 0.1.0
class: testing
author: navjyotnishant
---

# Test Repair (testing)

Fixes a test **when the test is what is broken**. Not the application, not the
assertion, not the gate.

> **This is the most dangerous skill in the class, and it ships last for that
> reason.** A self-healing test agent with soft constraints converges on
> green-by-deletion — and nobody notices for two months, because the suite is
> passing. A weakened assertion looks identical to a fixed test from the outside.
> The only signal is the diff, and the diff is exactly what stops being read once
> the suite is "reliable".
>
> Everything below exists to make that outcome impossible rather than unlikely.

This is a **testing-class** skill — follow `CONVENTIONS-testing.md`. `§T2` is not one
constraint among several here; it is the skill's shape. Also `§T1` source fence,
`§T6` propose the commit, `§T7` budget.

> **Finding the conventions file.** It lives at the toolkit repo root, two levels
> above this skill — not beside `SKILL.md`. Skills are usually installed as
> symlinks into your runner's skills directory, so a plain relative path resolves
> against the *link* and misses it. Resolve the link first:
>
> ```bash
> ROOT="$(dirname "$(readlink -f "<this skill's base directory>")")/.."
> ```
>
> then read `$ROOT/CONVENTIONS-testing.md` and `$ROOT/CONVENTIONS.md`. If a file is
> genuinely absent, say so and continue with the procedure below rather than stopping.

> **Every skill follows `CONVENTIONS-orchestration.md` §U** — ground everything in
> the actual repo, never run git on your own initiative, no secrets in output,
> keep `CHANGELOG.md` current when the change is user-facing, degrade rather than
> fail, and say what you did not do.

## Dependencies

Detected at runtime, never installed by this skill (`§T5`).

| Tool | Used for | Without it |
|---|---|---|
| `/test-triage` classification | knowing this failure is a test bug | **BLOCK** — this skill does not classify, and repairing an unclassified failure is how a real defect gets papered over |
| the run manifest + artifacts (`§T13`) | the actual failure evidence | **BLOCK** — a repair without evidence is a guess at the codebase |
| the repo's own test framework | idiomatic waits and selectors | SKIP — never impose a pattern from another framework |

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  TEST REPAIR — TESTING                                            ║
╠══════════════════════════════════════════════════════════════════╣
║  Fires ONLY on failures /test-triage called a test bug.           ║
║                                                                   ║
║  MAY fix:  selectors · waits · setup · teardown · wrong fixture   ║
║  MAY NOT:  weaken or delete an assertion · add a sleep · raise a  ║
║            retry · add a skip. Assertion changes ESCALATE.        ║
║                                                                   ║
║  If the real fix is in app code, it says so and STOPS.            ║
║  Proposes a diff. Never commits, never merges.                    ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **A `test-bug` classification** from `/test-triage`, with its evidence. Anything
  else → **BLOCK**. See Step 1.
- **The failure evidence** — manifest and artifacts (`§T13`, read in place per `§T4`).
- **A repair budget** (`§T7`). Default it, state it, and honour it.

## Step 1 — Refuse anything not classified `test-bug` (the gate)

This skill **does not classify**. It acts on `/test-triage`'s verdict and nothing
else:

| Classification | Action |
|---|---|
| `test bug` | proceed |
| `real defect` | **BLOCK** — the application is wrong; repairing the test hides it |
| `environment` | **BLOCK** — nothing in the test is broken |
| `flake` | **BLOCK** — see below |
| `data` | **BLOCK** — `/test-data` owns fixtures and seeding |
| unclassified | **BLOCK** — run `/test-triage` first |

> **`flake` is a BLOCK, and that is deliberate.** A flaky test is the most tempting
> thing in this list to "repair", and every available repair for it is forbidden: a
> sleep, a retry, a loosened assertion. The honest responses are a real fix for the
> underlying race, or quarantine with an SLA via `/flake-watch`. Making it pass is
> not one of them.

## Step 2 — Confirm the test is genuinely at fault

`/test-triage` said test-bug. Verify it against the evidence before changing
anything, because a misclassification here becomes a hidden defect.

The question to answer: **does the application behave correctly, and the test
disagree?**

- The markup changed intentionally and the selector is stale → **test bug**.
- The wait races a legitimate render → **test bug**.
- The fixture expects a shape the API deliberately no longer returns → **test bug**.
- The app returns the wrong value, and the assertion is right → **not a test bug.**
  Report it and stop, whatever the classification said.

**Disagreeing with the classification is allowed and expected.** If the evidence says
defect and the label says test-bug, the evidence wins — stop, and say why. A repair
skill that defers to a wrong label is the mechanism by which a defect gets closed.

## Step 3 — Repair, inside `§T2`

**May:**

- fix a selector that no longer matches — prefer the repo's testid convention over
  re-deriving a structural path
- replace a brittle wait with a proper condition — wait for the state, not a duration
- correct setup and teardown
- fix a genuinely wrong fixture or its wiring

**May not, under any circumstances:**

- weaken or delete an assertion
- add a fixed `sleep`
- raise a retry count
- add a `skip`, `.only`, `xit`, or any other suppression

**Anything touching an assertion escalates** — it does not appear in the proposed
diff. Say what would need to change and why, and let a human decide. An assertion is
the statement of what the software must do; changing it is a product decision wearing
a maintenance costume.

> These are not defaults to be weighed against convenience. If the only way to make
> a test pass is a forbidden change, **the correct output is a report saying so** —
> not a smaller version of the forbidden change. The constraint has to hold when it
> is inconvenient, or it does not hold.

## Step 4 — Stop at the fence (`§T1`)

If the correct fix is in **application source**, report it and stop. That is a real
finding: "the test is right and the app needs to change" is exactly the information a
reviewer wants.

Never edit app code to make a test pass. That inverts the entire purpose of the
suite, and it is the failure mode with the longest half-life — nobody re-reads a
green test.

## Step 5 — Respect the budget (`§T7`)

State the max attempts up front and hold to it. On exhaustion: **WARN with what was
tried and what remains failing.** Never a silent give-up, never an unbounded loop.

Two failed repair attempts on the same spec is a signal that the diagnosis is wrong,
not that a third attempt is needed. Stop and report.

## Step 6 — Propose the diff (`§T6`)

Show the diff, then the commands. Never run git, never merge.

Attach the failing trace **by path** (`§T4` — artifacts do not leave the temp dir), so
a reviewer can see the failure this claims to fix.

```
## Repair proposal — <n> of <m> test-bug failures

Budget: <used>/<max> attempts

  <spec>  selector
    - await page.click('.btn-primary:nth-child(2)')
    + await page.click('[data-testid="submit"]')
    why:  markup reordered in <sha>; the assertion is unchanged
    trace: <temp path> — view with <command>

  <spec>  ESCALATED — needs human review
    the only fix touches the assertion (expects 3 items, API now returns 2).
    That is a product question, not a maintenance one. Not in the diff.

  <spec>  BLOCKED — the fix is in application source
    <file:line> returns null where the contract says an empty array.
    The test is right.

Not repaired: <spec ids and why>
Nothing was committed.
```

```bash
git add <the spec files>
git commit -m "test(<scope>): fix stale selector after <what changed>"
```

## Safety rails

- **Only on `test-bug`** (Step 1). Every other classification BLOCKs, including
  `flake` — every available repair for a flake is forbidden.
- **Never weakens or deletes an assertion, adds a sleep, raises a retry, or adds a
  skip** (`§T2`). Assertion changes escalate; they never appear in the diff.
- **Never edits application source** (`§T1`). If the fix belongs there, report and
  stop.
- **Evidence outranks the label.** If the failure looks like a defect, stop, even
  when `/test-triage` said test-bug.
- **Budget honoured, exhaustion reported** (`§T7`). Two failures means the diagnosis
  is wrong, not that a third try is due.
- **Never commits, never merges, never `--no-verify`** (`§T6`).
- **Artifacts stay in the temp dir** (`§T4`) — referenced by path, never attached.
- **A harness error is not a pass** (`CONVENTIONS.md §5`).
