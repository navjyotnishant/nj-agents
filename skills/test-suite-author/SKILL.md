---
name: test-suite-author
description: "Use this skill when the user asks to \"write the tests for this ticket\", \"build a test suite for this requirement\", \"go from ticket to specs\", or wants the whole generation chain rather than three separate invocations. Umbrella over /test-plan → /test-author → /test-data: plans the cases, generates specs in the repo's own framework, and adds fixtures. PAUSES after every stage for review by default; --yes runs unattended for a workflow. Writes only inside detected test directories and PROPOSES the commit — never runs git. Works in any git repo; nothing here is project-specific."
version: 0.1.0
class: testing
author: navjyotnishant
---

# Test Suite Author (testing — umbrella)

Ticket in, reviewed specs out. Chains `/test-plan` → `/test-author` → `/test-data`
so a requirement becomes a suite in one invocation rather than three.

The three still work standalone, and that is deliberate (`§T13`) — this skill
sequences them, it does not absorb them. A stage that can only run inside a pipeline
cannot be verified on its own.

This is the **generation** umbrella. `/e2e-suite` is the execution one: run, triage,
verdict. Keeping them apart matters — generation writes source and proposes a commit,
execution runs code and returns a gate result. One umbrella doing both would have no
coherent verdict.

This is a **testing-class** skill — follow `CONVENTIONS-testing.md`: `§T1` source
fence, `§T2` never weaken an assertion, `§T5` detect never install, `§T6` propose the
commit, `§T8` no credentials in fixtures, `§T13` the run manifest.

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

> **Spawning subagents — `CONVENTIONS-orchestration.md`.** This skill spawns agents,
> so `§C` (cost) and `§R` (progress reporting) apply. **Cost shape:** three stages,
> roughly one agent call each — cost scales with the number of *cases*, not the size
> of the repo. State it and get a yes before the first dispatch; cap fix rounds at 2;
> halt on any signal to stop. Announce the **roster** up front and mark each stage as
> it lands (`§R`).

## The guardrails, and why each exists

**1. Pause after every stage.** Default behaviour. Each stage's output is reviewable
*before* the next one consumes it, because each is wrong in a different way and the
cheapest place to catch each is immediately after it.

**2. `--yes` skips the pauses.** For a workflow or a pipeline. Everything else still
holds — the fence, the assertion rule, the propose-commit. `--yes` removes the
*prompts*, never the *constraints*.

**3. Nothing is committed, ever.** Not with `--yes`, not in CI, not on request. The
chain ends at a diff and the exact git commands (`§T6`). A generation umbrella that
could commit would be the one skill in this class able to put unreviewed test code
into a repo.

**4. A stage that BLOCKs stops the chain.** No framework detected → SKIP, do not
proceed to author specs for a framework that is not there. No requirement → stop, do
not invent scope from the codebase.

**5. Cases are the review point.** If you read only one stage, read the plan. Twelve
well-chosen cases beat sixty generated permutations — but only if somebody sees the
twelve. Downstream stages are mechanical; the plan is where judgement lives.

## Dependencies

Detected at runtime, never installed by this skill (`§T5`).

| Tool | Used for | Without it |
|---|---|---|
| `/test-plan` | the case matrix | **BLOCK** — nothing to generate from |
| `/test-author` | specs in the repo's framework | plan only; report that specs were not written |
| `/test-data` | fixtures and factories | specs only; say fixtures were skipped |
| a detected test framework | knowing what a spec looks like here | **SKIP at the author stage** — never pick one |
| a connected tracker (MCP) | reading the requirement | paste-in fallback (`§A5`) |

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  TEST SUITE AUTHOR — TESTING (umbrella)                           ║
╠══════════════════════════════════════════════════════════════════╣
║  Ticket → cases → specs → fixtures, in one run.                   ║
║  PAUSES after every stage so you review before the next one       ║
║  consumes it. --yes skips the prompts for a workflow.             ║
║                                                                   ║
║  Writes only inside detected test directories. NEVER commits —    ║
║  not with --yes, not in CI. The chain ends at a diff.             ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **A requirement** — a ticket key, or pasted markdown. None → stop and ask. A plan
  built from the codebase alone is a guess about intent (`§U`).
- **A detected test framework**, for the author stage (`§T5`). None → the plan still
  runs and is still useful; say specs were not written and why.

## Step 1 — State the cost and the roster (`§C`, `§R`)

Cost scales with **cases, not repo size**. A ticket yielding 8 cases is cheap; one
yielding 40 is not.

```
Plan: /test-plan → /test-author → /test-data
      ~1 agent call per stage. Pausing after each (--yes to skip).
Proceed?
```

With `--yes`, or in CI (`NJ_AGENTS_CI=1`), there is nobody to ask: state the cost,
proceed, and report what it actually cost at the end (`§T10`).

## Step 2 — Plan (`/test-plan`)

Delegate. Do not re-derive the cases here — two case-generators in one chain is two
opinions that disagree.

**PAUSE.** Show the matrix by dimension, mark `new` / `covered` / `inferred`, and
wait.

```
PLAN — 14 cases    equivalence 4 · boundary 5 · negative 3 · authz 2
  3 marked inferred — not stated in the requirement, review these first
  2 already covered by <existing tests>

  [y] generate specs   [e] edit the plan   [n] stop here (the plan is still useful)
```

**Read the inferred ones.** They are where the planner is guessing at intent, and
they are cheapest to correct now — before they become specs, and long before they
become specs somebody trusts.

## Step 2.5 — File the approved cases as tracker sub-tasks (`§P3`, `§P4`, `§P5`)

An approved plan that lives only in a temp file is invisible to everyone but the
person who ran it, and a re-run regenerates it from nothing. File the **uncovered**
cases as sub-tasks under the parent ticket so each one has a state a team can see.

**Naming convention — `TEST-` prefix on every title:**

```
TEST-NEG-06   Dry-run writes nothing
TEST-AUTHZ-01 Unauthenticated upload refused
TEST-BND-02   Numeric(14,2) ceiling, both sides
```

The prefix is the point: these sit in the same backlog as feature work, and a reader
scanning a sprint needs to tell coverage tasks from product tasks at a glance. It is
also what makes them findable for the search-before-create below.

**Only the uncovered ones.** A case already covered by an existing test is not work —
filing it creates a ticket whose acceptance criteria are already met, which is noise
that trains people to ignore the prefix.

Delegate the creates to `/pm-task` rather than writing a tracker client here
(`/test-triage` already does this for defects). Then the PM-class rules apply and
they are not optional:

- **`§P4` search before create.** Query the parent for existing `TEST-` sub-tasks
  first and reconcile. A second run of this skill on the same ticket must **link**
  what exists rather than filing 16 duplicates — and a second run is the normal case,
  because a requirement changes and the plan is regenerated.
- **`§P5` sequential, parent-first.** Create under the parent, one at a time,
  capturing each ID. On any failure, **halt and report** what was created and what
  was not — never retry-storm, never leave a half-filed tree silent.
- **`§P3` one explicit opt-in** covers the batch, shown as a preview first. Sixteen
  creates is exactly the case that must not fire off an ambiguous "ok".
- **`§P6` MCP detected, never required.** No tracker connected → print the sub-tasks
  as paste-ready markdown and carry on. Filing is a convenience; the plan is the
  deliverable.

**PAUSE** before creating anything:

```
FILE 16 sub-tasks under ENG-159?    (9 covered/partial — not filed)

  TEST-NEG-06    Dry-run writes nothing              critical
  TEST-AUTHZ-01  Unauthenticated upload refused      critical
  TEST-AUTHZ-02  No contacts permission → 403        critical
  ... 13 more

  Existing TEST- sub-tasks found: 0 — nothing to reconcile
  [y] create   [n] skip — plan stays in the manifest   [e] trim the list
```

With `--yes`, file them without pausing. The `§P4` reconcile still runs, and a
partial failure still halts — `--yes` removes the prompt, never the discipline.

Skipping this stage is fine and costs nothing downstream: `/test-author` reads the
plan from the manifest, not from the tracker.

## Step 3 — Author (`/test-author`)

Delegate. Specs go into the detected test directory, in the repo's own framework,
matching the style of an existing spec.

**PAUSE.** Show what was written and what was flagged.

```
SPECS — 6 files from 14 cases
  brittle selectors flagged: 2   ← the app has no testid for these
  cases not expressed: 1 — <why>

  [y] add fixtures   [e] revise   [n] stop — specs are written, commit them yourself
```

**If the app has no testids**, this stage proposes adding them and does **not** add
them itself — that is application source, outside `§T1`. A spec keyed to markup
structure because the testids are missing is worse than a report saying they are
missing.

## Step 4 — Data (`/test-data`)

Delegate. Fixtures and factories so each spec owns its data.

**PAUSE.** Show the factories, their uniqueness strategy, and what persists.

```
FIXTURES — 3 factories, 1 seed helper
  unique per run: run-scoped prefix
  cleanup: 2 automatic, 1 manual — <why>
  credentials: from <VAR>, <VAR> — none written to disk

  [y] show the commit block   [n] stop
```

Skip this stage entirely when the specs need no data beyond what exists. An empty
fixture file is worse than none — it becomes the pattern someone copies.

## Step 5 — Propose the commit (`§T6`)

Diff, then the exact commands. **Never run git**, whatever flags were passed.

```bash
git add tests/specs/ tests/fixtures/
git commit -m "test(<scope>): add coverage for <requirement>"
```

Report format:

```
## Test suite — <requirement>

Framework:  <detected>        Test root: <path>
Cases:      <n>  (<k> new, <m> covered, <i> inferred)
Specs:      <n> files         Fixtures: <n> factories
Cost:       <tokens/calls per stage>

Flagged:
  <n> brittle selectors — <file:line>
  <n> cases not expressible — <why>
Needs a human change:
  testids missing in <component> — app source, outside §T1

Nothing was committed. Commands above are yours to run.
Not done: <stages skipped, and why>
```

## Safety rails

- **Never commits.** Not with `--yes`, not in CI, not on request (`§T6`). The chain
  ends at a diff.
- **Never weakens an assertion** to make a generated spec pass (`§T2`). A case that
  cannot be expressed is reported, not softened.
- **Writes only inside detected test directories** (`§T1`). Never app source — if a
  testid or a seed hook is needed, propose it and stop.
- **Never picks a framework** (`§T5`). None detected → the author stage SKIPs; the
  plan still stands.
- **Never writes a credential** to disk (`§T8`) — env only, document the name.
- **`--yes` removes prompts, not constraints.** Every rail above holds identically
  unattended. If a stage would BLOCK interactively, it BLOCKs with `--yes` too.
- **A BLOCK stops the chain** — never proceed to the next stage on a failed one.
- **State the cost before the first dispatch, cap fix rounds at 2, halt on any stop
  signal** (`§C`).
