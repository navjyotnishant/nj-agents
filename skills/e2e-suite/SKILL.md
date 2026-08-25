---
name: e2e-suite
description: "Use this skill when the user asks to \"run the full e2e suite\", \"e2e gate before release\", \"run and triage the browser tests\", or wants one entry point that runs the suite, classifies every failure, and returns a single verdict. Umbrella over the testing class: /e2e-run captures evidence, /test-triage classifies it, /flake-watch supplies history, /test-report writes the matrix. Aggregates one PASS / WARN / BLOCK and honours the CI exit-code contract. Never repairs anything. Works in any git repo; nothing here is project-specific."
version: 0.1.0
class: testing
author: navjyotnishant
---

# E2E Suite (testing — umbrella)

One entry point: run the suite, classify every failure, and return **one verdict**.

It orchestrates skills that each work standalone — `/e2e-run` captures evidence,
`/test-triage` classifies it, `/flake-watch` supplies history, `/test-report` writes
the traceability matrix. This skill sequences them and aggregates the result, the way
`/pre-push-review` does for the review dimensions.

It **never repairs anything.** `/test-repair` is deliberately outside this pipeline:
a gate that can fix its own failures is not a gate. Repair is a separate, human-
initiated act on a specific classified failure.

This is a **testing-class** skill — follow `CONVENTIONS-testing.md`. As the umbrella
it inherits every clause its children carry, and owns `§T11` parallel execution and
`§T13` the manifest all of them share.

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

> **Spawning subagents — `CONVENTIONS-orchestration.md`.** This skill spawns agents
> via a `Workflow`-tool pipeline (Step 3), so `§C` (cost) and `§R` (progress
> reporting) apply. **Cost shape:** one run plus per-failure triage, fanned out
> under a concurrency cap — cost scales with the number of *failures*, not the
> size of the suite. State it and get a yes before the first dispatch; cap fix
> rounds at 2; halt on any signal to stop. Announce the **roster** before dispatch
> and mark each stage as it lands (`§R`). The run is resumable via
> `resumeFromRunId` if interrupted (`§M1`) — worth mentioning on failure, not a
> dedicated section, since a pure-`parallel()` fleet like this one has little
> sunk cost to preserve on resume.

**This skill writes nothing into the repo.** It runs, reads, aggregates and reports —
`§T1`'s fence has nothing to fence. The only file it produces is the report artifact,
outside the repo tree.

## Dependencies

Detected at runtime, never installed by this skill (`§T5`).

| Tool | Used for | Without it |
|---|---|---|
| `nj-run` (this toolkit, `bin/`) | manifest, cost, subagent records, deterministic aggregation (`§T10`–`§T13`) | aggregate by hand per Step 4's table; say cost and subagent records are missing |
| `/e2e-run` | executing the suite and capturing evidence | **BLOCK** — nothing to aggregate |
| `/test-triage` | classifying each failure | report raw failures, verdict **WARN**, and say classification was unavailable |
| `/flake-watch` + the ledger | flake history | triage runs without the flake class; say so |
| `/test-report` | the traceability matrix | report without it, and say so |

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  E2E SUITE — TESTING (umbrella)                                   ║
╠══════════════════════════════════════════════════════════════════╣
║  Runs your suite, classifies every failure, returns ONE verdict.  ║
║  BLOCKS unless the base URL is explicitly non-production.         ║
║                                                                   ║
║  Artifacts stay in a gitignored temp dir; published text is       ║
║  secret-scrubbed. It NEVER repairs a test — a gate that fixes     ║
║  its own failures is not a gate.                                  ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **An explicit non-prod base URL** (`§T3`) — `/e2e-run` gates on it; this skill
  surfaces that BLOCK rather than working around it.
- **A detected E2E runner** (`§T5`). None → SKIP the whole pipeline with the reason.

## Step 1 — State the cost, then confirm (`§C`)

Cost here scales with **failures, not specs**: the run is one cost, and triage fans
out per failure. A green suite is nearly free; a hundred red specs is not.

```
Plan: /e2e-run (1 run) → triage <n> failures in parallel (cap <k>) → report
      Estimated: 1 + <n> agent calls
Proceed?
```

In non-interactive/CI mode there is nobody to ask (`CONVENTIONS.md §5`): proceed, but
still honour the budget and report what it cost (`§T10`).

## Step 2 — Run (`/e2e-run`)

Delegate. Do not reimplement detection, the URL gate, or capture — this skill's value
is sequencing, and a second implementation of the `§T3` gate is a second thing to keep
correct.

**A BLOCK from `/e2e-run` is the final answer.** Surface it and stop; never retry
against a different URL, and never lower the gate to get a result.

## Step 3 — Triage the failures via a Workflow pipeline (`§T11`)

Zero failures → skip triage entirely and report PASS. Do not spend an agent
confirming nothing is wrong.

Otherwise, hand this script to the `Workflow` tool. It **spawns the
`failure-triager` agent's persona** once per failure, in parallel, under the
concurrency cap recorded at `nj-run init` — replacing what used to be manual
"spawn N agents" prose with a scripted `parallel()` call. `nj-run spawn`/`join`
stay exactly as they were: pure bookkeeping calls made from *inside* the script
around each `agent()` call, not the dispatch mechanism itself — `nj-run`'s
aggregation (`cmd_aggregate`/`cmd_finish`) reduces over the manifest and has never
cared how a subagent was actually spawned, so none of its guarantees (quarantine
forces BLOCK, order-independent reduce, §T11) change with this migration.

```js
export const meta = {
  name: 'e2e-suite-triage',
  description: 'Per-failure triage in parallel, schema-validated before aggregation',
  phases: [
    { title: 'Triage', detail: 'failure-triager per failure, concurrency-capped' },
  ],
}

// Inlined from agents/failure-triager.md's core instructions, NOT passed via
// opts.agentType. failure-triager is a brand-new agent — live-tested and
// confirmed the Workflow tool's registry does not yet include it
// (opts.agentType: 'failure-triager' throws "agent type not found"), the exact
// registry-lag bug security-deep-review's own build hit for security-finder/
// security-verifier. Inline prompts have no such dependency. Re-verify with
// opts.agentType once the agent has been installed for a while (see
// security-deep-review/SKILL.md's note on this being a timing issue, not
// permanent) rather than assuming this stays inline forever.
const TRIAGER_PERSONA = `You are a test-failure triager working one failure at a time. Given a single failure's evidence (manifest entry, diff since last green, flake-ledger history for that spec), classify it as exactly one of: real_defect, test_bug, environment, flake, data, or not_determined. A classification without cited evidence is an opinion, not a triage. Never classify flake without ledger history for this specific spec — timing-flavored failure text is not evidence of flakiness, a real race condition looks identical, and without ledger history the flake class is unavailable for this failure. Bias toward real_defect when genuinely uncertain, with a stated low confidence — a defect miscalled a flake is ignored, a flake miscalled a defect costs twenty minutes; prefer the cheap error. Correlate to a suspect commit via the diff since last green if provided, stating why the commit is suspect, not just that it's recent. Read-only: never modify files, never run git push/commit, never update the flake ledger yourself. Return the bare spec filename in the "spec" field (e.g. "checkout.spec.ts"), not a restated summary of the failure.`

const TRIAGE_SCHEMA = { type: 'object', properties: {
  spec: { type: 'string' },
  class: { type: 'string', enum: ['real_defect', 'test_bug', 'environment', 'flake', 'data', 'not_determined'] },
  confidence: { type: 'number' },
  evidence: { type: 'string' },
  suspect_commit: { type: 'string' },
}, required: ['spec', 'class', 'confidence', 'evidence'] }

phase('Triage')
const results = (await parallel(failures.map(f => () =>
  agent(
    `${TRIAGER_PERSONA}\n\n${buildTriagePrompt(f, diffSinceGreen, flakeLedgerFor(f.spec))}`,
    { label: `triage:${f.spec}`, phase: 'Triage', schema: TRIAGE_SCHEMA }
  ).then(r => r && { failure: f, ...r })
))).filter(Boolean)

return { results, attempted: failures.length, completed: results.length }
```

Record the fan-out through the harness as each result lands — the concurrency cap
comes from `--concurrency` at `init` (or `NJ_RUN_CONCURRENCY`), so the cap in force
is recorded with the run instead of being an unwritten decision:

```bash
# for each failure, before/after its agent() call resolves:
id="$(nj-run spawn failure-triager)"
# … the Workflow script's agent() call for that failure resolves …
nj-run join "$id" --status ok|failed --tokens <n> --calls <n>
```

Three rules make the verdict trustworthy, all unchanged by this migration since
they live in `nj-run`, not in how the fan-out is scripted:

- **Aggregation order is deterministic**, independent of completion order. The same
  inputs must produce the same verdict — a gate whose result depends on which
  subagent finished first is not a gate.
- **A subagent failure is quarantined and reported, never dropped.** `results.length
  < attempted` (a `parallel()` call whose `agent()` errored resolves to `null`,
  filtered above) means fewer triages completed than were dispatched — join that
  gap as `--status failed` per `§T11`, never silently treat a partial result set as
  a complete one.
- **Announce the roster, mark each as it lands** (`§R`), so a stall is attributable
  to a named failure rather than to the suite.

## Step 4 — Aggregate one verdict

Record each dimension, then let the harness reduce them:

```bash
nj-run verdict --dimension <name> --value PASS|WARN|BLOCK|SKIP
nj-run finish                    # aggregates, prints the report, exits per §5
```

`finish` applies the table below, and applies it the same way every time. Two
properties it enforces that a hand-written reduce tends to lose:

- **A quarantined subagent forces BLOCK** — it cannot be outvoted by the dimensions
  that did complete. Four of five triages completing is not a complete triage.
- **No dimensions, or all `SKIP`, is a PASS** (`§U`), not an ambiguous result that
  exits 2 and blocks a push for no reason.

The aggregation is order-independent because the reduce is over *set membership*, not
a sequence — so it stays correct however the subagents finish. Any new rule added here
must preserve that; "first BLOCK wins" or "last verdict wins" would quietly
reintroduce completion-order dependence.

| Verdict | When |
|---|---|
| **BLOCK** | any `real defect`, or the `§T3` gate refused, or triage could not run at all |
| **WARN** | only `flake` / `environment` / `data`, or a partial run, or a quarantined subagent |
| **PASS** | no failures |

**A test bug is a WARN, not a PASS.** The application is fine, but the suite is
lying — and a broken test that reports green is how coverage quietly disappears.

**Never resolve ambiguity toward PASS.** If the verdict cannot be determined, that is
a harness error (exit 2), not a pass. This is the whole reason the exit-code contract
exists: `claude -p` returns 0 whether a review passed, blocked, or never happened.

Exit codes (`CONVENTIONS.md §5`): `0` PASS or WARN · `1` BLOCK · `2` harness error.
In CI mode, ambiguity resolves to BLOCK.

## Step 5 — Report (`/test-report`, `§T4`)

Delegate the traceability matrix. Everything published is scrubbed first.

```
## E2E suite — <verdict>

Environment: <url> (allowed by: <§T3 rule>)     Runner: <detected>
Specs: <n>   Passed: <p>   Failed: <f>          Cost: <tokens/calls, wall clock>

  real defect   <n>   → BLOCK
  test bug      <n>   → WARN — the app is fine, the suite is lying
  flake         <n>   → known, see the ledger
  environment   <n>
  data          <n>
  unclassified  <n>   ← look here first

Artifacts: <temp path — local only, §T4>
Report:    <path>
Next:      /test-repair for the test bugs (test-bug only) · /pm-task for the defects

Not done: <specs skipped, evidence unavailable, subagents quarantined>
```

**Say what was not done.** A silent gap reads as a clean result, and this is the
report someone approves a release against.

## Safety rails

- **Never repairs anything.** `/test-repair` is outside this pipeline by design.
- **Never lowers the `§T3` gate** to get a result. A BLOCK from `/e2e-run` is final.
- **Never resolves ambiguity toward PASS** — no verdict is exit 2, and CI resolves
  ambiguity to BLOCK.
- **A test bug is WARN, never PASS.** A test that reports green while broken is how
  coverage disappears.
- **A quarantined subagent is reported, never dropped** (`§T11`) — a shrunken result
  set is a false PASS.
- **Deterministic aggregation** (`§T11`): same inputs, same verdict, whatever the
  completion order.
- **Writes nothing into the repo** (`§T1`); artifacts stay in the temp dir (`§T4`).
- **State the cost before spawning, cap rounds at 2, halt on any stop signal**
  (`§C`, `§T10`).
