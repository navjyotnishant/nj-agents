---
name: flake-watch
description: "Use this skill when the user asks \"which tests are flaky\", \"what should we quarantine\", \"show the flake report\", or wants per-spec failure history rather than a single run's result. Reads the committed flake ledger and reports fail rate per spec over the last N runs, which specs are trending worse, and which cross the quarantine threshold. Quarantine is always a PROPOSAL carrying an SLA and a tracking issue — never applied silently. Advises only: it writes no test and skips nothing. Works in any git repo; nothing here is project-specific."
version: 0.1.0
class: testing
author: navjyotnishant
---

# Flake Watch (testing)

Reports what the **flake ledger** knows: which specs fail intermittently, how often,
and which have crossed the point where they cost more than they catch.

A single run cannot tell a flake from a regression. History can. That is the whole
reason the ledger is committed rather than gitignored (`§T14`) — gitignored it would
start empty on every CI runner, which is exactly where intermittent failures
accumulate unwatched.

This skill is the ledger's **reader and reporter**. `/test-triage` writes to it as a
side effect of classifying a run; this one reads the accumulated picture and says
what to do about it.

This is a **testing-class** skill — follow `CONVENTIONS-testing.md`. The clauses that
bind this one: `§T14` the ledger itself, `§T4` scrub anything published.

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

**This skill is read-only over the repo.** It writes no test, skips nothing, and
quarantines nothing — `§T1`'s source fence has nothing to fence. It reads the ledger
and reports. A quarantine is a **proposal**, and applying one is the user's call.

## Dependencies

Detected at runtime, never installed by this skill (`§T5`).

| Tool | Used for | Without it |
|---|---|---|
| the flake ledger (`§T14`) | everything this skill does | **SKIP** with a labeled reason — there is no history to report, and inventing one is worse than reporting none |
| `git` | showing when a spec started failing | report rates without the timeline, and say so |
| a connected PM tracker (MCP) | opening the tracking issue a quarantine requires | print the issue as paste-ready markdown (`§A5` detect-never-require) |

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  FLAKE WATCH — TESTING                                            ║
╠══════════════════════════════════════════════════════════════════╣
║  Reads the committed flake ledger: fail rate per spec over the    ║
║  last N runs, what is trending worse, what crosses the            ║
║  quarantine threshold.                                            ║
║                                                                   ║
║  Quarantine is PROPOSED, never applied. Every proposal carries    ║
║  an SLA and a tracking issue — a spec dropped from the gate with  ║
║  no owner is a spec deleted slowly.                               ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **A flake ledger** at `.nj-agents/flake-ledger.json` (`§T14`). Absent → SKIP with
  the reason: no history means no flake analysis, and a guess dressed as a rate is
  worse than silence.
- **Enough runs to mean something.** See the sample-size rule below.

## Step 1 — Read the ledger (`§T14`)

Per spec and assertion: fail count, run count, the window they cover, and current
quarantine state.

**Records survive renames.** A spec keyed on path alone loses its history the first
time someone reorganises a directory — and a chronically unstable spec then gets a
clean slate it did not earn. Reconcile on the stable identifier first, path second,
and say when a record was matched by fallback rather than identity.

## Step 2 — Compute rates, and respect the sample size

Fail rate per spec over the window. Then the part that is easy to get wrong:

**A rate needs a denominator worth trusting.** One failure in three runs is 33% and
means nothing. Report specs below the minimum sample as **"insufficient history"**
rather than assigning them a rate — a number implies a confidence the data does not
support, and a 33% headline on three runs will be acted on.

**Trend matters more than the absolute rate.** A spec at a steady 4% for six months
is a known cost. A spec that went from 0% to 15% in the last twenty runs is a
regression someone introduced, and it should not sit in the same bucket. Report
direction, not just magnitude.

**A spec that fails 100% is not flaky — it is broken.** Say so, and route it to
`/test-triage` rather than into a quarantine proposal. Quarantining a consistently
failing test hides a real defect behind flake accounting, which is precisely the
failure mode the ledger exists to prevent.

## Step 3 — Propose quarantine, never apply it

A spec crossing the threshold gets a **proposal**, and every proposal carries:

- **why** — the rate, the window, and the trend
- **an SLA** — a date by which it is fixed or deliberately deleted
- **a tracking issue** — via `/pm-task` if a tracker is connected, else paste-ready
  markdown (`§A5`)
- **what stops being covered** — quarantine removes real coverage, and the report
  should say what is no longer being checked

> **Never quarantine silently, and never without an owner.** A spec removed from the
> gate with no date attached is a spec deleted slowly: nobody revisits it, the
> coverage quietly disappears, and six months later the quarantine list is the real
> test plan. The SLA is what makes it a decision rather than a drift.

Because the ledger is committed (`§T14`), a quarantine shows up as a **diff in a
PR** — reviewable by whoever owns the area. That visibility is a feature, not a
side effect.

## Step 4 — Report (`§T4`)

Everything published is scrubbed. The ledger itself holds only spec identity, counts
and dates by construction — nothing artifact-derived — so there should be nothing to
find. Scrub anyway: the cost is nil and the assumption is exactly the sort that stops
being true when someone adds a field.

```
## Flake watch — <N> specs with history, window: last <M> runs

Ledger: .nj-agents/flake-ledger.json   (<n> records, <k> matched by path fallback)

  Quarantine candidates
    <spec>          22%  (9/40)  ↑ from 4% over the last 20 runs
                    proposal: SLA <date> · issue <key or "markdown below">
                    coverage lost: <what this spec checks>

  Trending worse
    <spec>          11%  (4/36)  ↑ from 2%

  Known-stable flakes
    <spec>           4%  (2/50)  → flat, below threshold

  Not flaky — broken
    <spec>         100%  (40/40) → route to /test-triage, this is a defect

  Insufficient history
    <spec>          <5 runs — no rate reported

Nothing was quarantined. Proposals above are for you to apply.
```

## Safety rails

- **Advises only.** Writes no test, skips nothing, quarantines nothing. Read-only
  over the repo (`§T1`).
- **Never applies a quarantine** — proposals only, each with an SLA and a tracking
  issue (`§T14`).
- **Never reports a rate below the minimum sample.** "Insufficient history" is the
  honest answer; a percentage from three runs will be believed.
- **Never quarantines a 100% failure** — that is a defect wearing a flake costume.
  Route it to `/test-triage`.
- **Never invents history.** No ledger → SKIP with the reason, never a guess.
- **Scrub anything published** (`§T4`).
- **A harness error is not a pass** (`CONVENTIONS.md §5`): no ledger, no verdict,
  exit 2 in CI mode.
