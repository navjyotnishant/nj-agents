---
name: test-triage
description: "Use this skill when the user asks \"why did the tests fail\", \"is this a real bug or a flake\", \"triage the CI failures\", or wants a red build explained rather than re-run. Reads the run manifest from /e2e-run, the diff since last green, and the flake ledger, then classifies each failure as real defect, test bug, environment, flake, or data — each with a confidence and the evidence it cites. Correlates failures to suspect commits by blaming the changed lines. Advises only: it writes nothing, fixes nothing, and hands real defects to /pm-task. Works in any git repo; nothing here is project-specific."
version: 0.1.0
class: testing
author: navjyotnishant
---

# Test Triage (testing)

Explains a red build. For each failure it answers the only question that matters at
that moment — **is something actually broken?** — and cites the evidence for its
answer.

Five classifications, each with a confidence:

| Class | Means | Goes to |
|---|---|---|
| **real defect** | the application is wrong | `/pm-task` |
| **test bug** | the test is wrong, the app is fine | `/test-repair` |
| **environment** | infrastructure, not code | the report |
| **flake** | fails intermittently, independent of the diff | the flake ledger |
| **data** | fixture or seed state, not logic | the report |

> **This is the skill the class lives or dies on.** Generating tests is the easy half
> and largely solved. What decides whether a suite survives month three is whether
> the team trusts the gate. Weak triage teaches people that red means "run it again"
> — and once that habit forms, every skill upstream of it is shelfware. A wrong
> classification here is worse than no classification, because it is believed.

This is a **testing-class** skill — follow `CONVENTIONS-testing.md`. The clauses that
bind this one: `§T4` scrub anything published, `§T13` read the run manifest,
`§T14` read and update the flake ledger.

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

**This skill is read-only.** It writes nothing into the repo — no spec, no fix, no
config — so `§T1`'s source fence has nothing to fence. It reads evidence and reports
a judgement. The one thing it may update is the flake ledger (`§T14`), which is
history, not source.

## Dependencies

Detected at runtime, never installed by this skill (`§T5`).

| Tool | Used for | Without it |
|---|---|---|
| a run manifest from `/e2e-run` | the failures and their evidence | **BLOCK** — there is nothing to triage without it |
| `git` | blaming changed lines to find suspect commits | classify without commit correlation, and say so |
| the flake ledger (`§T14`) | separating flake from regression | **say the flake class is unavailable** — never guess it from one run |
| `gitleaks` *or* `trufflehog` *or* `detect-secrets` | scrubbing published text (`§T4`) | **BLOCK** before publishing anything |

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  TEST TRIAGE — TESTING                                            ║
╠══════════════════════════════════════════════════════════════════╣
║  Classifies each failure: real defect · test bug · environment   ║
║  · flake · data — with a confidence and the evidence cited.       ║
║                                                                   ║
║  ADVISES ONLY. It writes no code, fixes no test, and commits      ║
║  nothing. Real defects are handed to /pm-task on your say-so.     ║
║                                                                   ║
║  Anything it quotes from a trace is secret-scrubbed first.        ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A run manifest** from `/e2e-run` (`§T13`). No manifest → BLOCK: triage without
  evidence is guessing with extra steps.
- **A git repository**, for commit correlation. Absent → classify anyway, say what
  was unavailable.
- **The flake ledger**, ideally. Absent → the `flake` class cannot be used; see below.

## Step 1 — Read the evidence (`§T13`)

Three inputs, all read, none inferred:

1. **The run manifest** — failures, per-spec results, the environment and *which
   `§T3` rule allowed it*, and the artifacts dir.
2. **The diff since last green** — what actually changed. Without a last-green
   reference, say so; "everything is suspect" is a weaker but honest position.
3. **The flake ledger** (`§T14`) — historical fail rate per spec and assertion.

Read artifacts **in place**. They stay in the temp dir (`§T4`) — this skill does not
copy, attach, or move them.

## Step 2 — Classify each failure, with evidence

One classification per failure, each carrying **a confidence and the specific
evidence** that produced it. A classification without evidence is an opinion.

Signals that actually distinguish the classes:

- **real defect** — the failure reproduces, the assertion is reasonable, and the
  behaviour changed in the diff. Strongest when the blamed line is in the diff.
- **test bug** — the app behaves correctly and the *test* is wrong: a selector that
  no longer matches after a legitimate markup change, a wait racing a legitimate
  render, a stale fixture expectation.
- **environment** — connection refused, DNS, a 502 from a dependency, an expired
  certificate, the app never came up. Nothing about the code is implicated.
- **flake** — **the ledger says so.** Not "it looks timing-related". See below.
- **data** — a seed did not run, a fixture collided, a leftover record from an
  earlier spec. Frequently the real cause when several unrelated specs fail together.

**Never classify `flake` from a single run.** Timing-flavoured failure text is not
evidence of flakiness — a real race condition in the application looks exactly the
same, and calling it a flake is how a genuine concurrency bug gets ignored for a
quarter. Without ledger history saying this spec fails intermittently, classify on
what the evidence supports and say the flake class was unavailable.

> **Bias toward "real defect" when genuinely uncertain**, and say the confidence is
> low. The asymmetry matters: a defect miscalled a flake is ignored; a flake
> miscalled a defect costs somebody twenty minutes. Cheap error, expensive error —
> prefer the cheap one.

## Step 3 — Correlate to suspect commits

For each failure, blame the lines the failure touches and intersect that with the
diff since last green. Report the suspect commit(s) with **why** they are suspect —
"this commit changed the selector this test queries" is useful; "this commit is
recent" is not.

Multiple specs failing on one commit is a strong signal. One spec failing across
many commits is a ledger question, not a blame question.

## Step 4 — Update the flake ledger (`§T14`)

Record this run's outcome per spec — pass/fail only, plus the date. **Nothing derived
from an artifact goes into the ledger**: spec identity, counts and dates only, so
there is nothing in it to scrub later.

Write **only if a value changed**, keep it sorted, one record per line — the file is
committed (`§T14`) and a noisy diff on every run is the cost that decision accepted.

If a spec crosses the quarantine threshold, **propose** quarantine with an SLA and a
tracking issue. Never quarantine silently: a spec dropped from the gate with no owner
and no date is a spec deleted slowly.

## Step 5 — Report, and hand off (`§T4`)

Everything published is scrubbed first. Failure messages and request URLs come out of
a real session against a real app — a bearer token in a query string or a session ID
in an error message reaches the report with no artifact ever moving.

```
## Triage — <N> failures

Manifest:   <path>          Environment: <url> (allowed by: <§T3 rule>)
Ledger:     <path>          Diff since green: <range, or "unavailable">

  real defect   <spec>  conf: high
                <scrubbed failure message>
                suspect: <sha> — changed the selector this spec queries
  test bug      <spec>  conf: medium
                selector .btn-submit no longer exists; markup change looks intentional
  flake         <spec>  conf: high
                ledger: failed 7 of last 40 runs, unrelated to this diff
  environment   <spec>  conf: high
                connection refused — the app never came up

Verdict: PASS | WARN | BLOCK
Next:    /pm-task for the defect · /test-repair for the test bug
Ledger:  <n> records updated · <spec> proposed for quarantine (SLA: <date>)

Not determined: <failures with no confident class, and what evidence was missing>
```

**Say what you could not classify.** A triage that forces every failure into a
category is less useful than one that admits two were unclear — the unclear ones are
where a human should look first.

Real defects hand off to `/pm-task` **on the user's say-so**, never automatically;
filing tickets unprompted is how a tracker fills with noise.

## Safety rails

- **Advises only.** Writes no spec, no fix, no config. The flake ledger is the single
  exception, and it holds history, not source (`§T1`, `§T14`).
- **Never weakens or skips a test** to resolve a failure — that is `/test-repair`'s
  constrained job, under `§T2`, and this skill has no repair path at all.
- **Never classifies `flake` without ledger history.** One run cannot distinguish a
  flake from a race condition in the application.
- **Never files a ticket unprompted** — hand off on an explicit go-ahead.
- **Scrub every published string** (`§T4`). Artifacts stay in the temp dir; this skill
  reads them there and copies nothing out.
- **Never quarantine silently** — a proposal carries an SLA and a tracking issue.
- **A harness error is not a pass** (`CONVENTIONS.md §5`): no manifest, no verdict,
  exit 2.
