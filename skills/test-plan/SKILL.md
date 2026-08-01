---
name: test-plan
description: "Use this skill when the user asks to \"plan the tests for this ticket\", \"what should we test here\", \"build a test case matrix\", or wants a requirement turned into structured test cases before anyone writes a spec. Ingests a requirement from a connected tracker (Linear/Jira/Notion/GitHub Issues) or pasted markdown, consumes /test-gap-finder's coverage output rather than reimplementing it, and emits structured case objects covering equivalence classes, boundaries, negative paths and authz. Advises only: it writes no spec and no file. Works in any git repo; nothing here is project-specific."
version: 0.1.0
class: testing
author: navjyotnishant
---

# Test Plan (testing)

Turns a requirement into a **structured case matrix** — before anyone writes a spec.

The point is coverage of the paths that matter, not the paths that are obvious. Left
to itself, spec generation writes the happy path and stops: it is the easiest thing
to derive from a ticket, and it is the case least likely to break. The interesting
failures live in boundaries, negative paths, and authorization.

Output is **structured case objects (JSON), not prose.** `/test-author` consumes them
directly, so a paragraph describing what to test would have to be re-parsed and
re-interpreted — which is where intent gets lost.

This is a **testing-class** skill — follow `CONVENTIONS-testing.md`. The clauses that
bind this one: `§T4` scrub anything published, `§T9` structured output, `§T13` write
the plan into the run manifest.

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

**This skill is read-only.** It writes no spec, no fixture, no file into the repo —
`§T1`'s source fence has nothing to fence. It produces a plan; `/test-author` turns
that into code, under its own constraints.

## Dependencies

Detected at runtime, never installed by this skill (`§T5`).

| Tool | Used for | Without it |
|---|---|---|
| a connected PM tracker (MCP) | reading the requirement | **paste-ready fallback** — the user pastes the requirement as markdown (`§A5`) |
| `/test-gap-finder` | which paths already have coverage | plan against the requirement alone, and **say the plan may duplicate existing tests** |
| `gitleaks` *or* `trufflehog` *or* `detect-secrets` | scrubbing published text (`§T4`) | **BLOCK** before publishing anything |

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  TEST PLAN — TESTING                                              ║
╠══════════════════════════════════════════════════════════════════╣
║  Turns a requirement into a structured case matrix: equivalence   ║
║  classes, boundaries, negative paths, authz — not just the        ║
║  happy path.                                                      ║
║                                                                   ║
║  Reads a ticket (via a connected tracker, or pasted markdown)     ║
║  and existing coverage. Emits JSON case objects for /test-author. ║
║  ADVISES ONLY — it writes no spec and no file.                    ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **A requirement.** From a tracker if one is connected, else pasted. No requirement
  → stop and ask; a plan invented from the codebase alone is a guess about intent.
- **Ideally, coverage output** from `/test-gap-finder`. Absent → plan anyway, and say
  the result may propose cases that already exist.

## Step 1 — Ingest the requirement (`§A5` detect, never require)

This is the first skill in the suite that reads **from** a tracker — the `/pm-*`
skills write to one. Reuse their discipline (`CONVENTIONS-pm.md §P6`): probe for a
connected MCP, use it if present, and fall back cleanly if not.

- **Tracker connected** → read the issue: title, description, acceptance criteria,
  and any linked spec or design doc.
- **No tracker, or the user declines** → ask for the requirement as pasted markdown.
  The fallback is a first-class path, not a degraded one.

**Ground the plan in what the requirement says** (`§U`). Where a case is inferred
rather than stated, mark it `inferred` so a reviewer can see which cases came from
the ticket and which came from judgement. Do not invent scope: a requirement about a
login form is not an invitation to plan password-reset coverage.

## Step 2 — Read existing coverage, do not recompute it

`/test-gap-finder` already maps code paths to tests and detects the repo's coverage
tooling. **Consume its output.** Keep the boundary sharp or the two develop divergent
heuristics and disagree about the same file — at which point neither is trusted.

Use it to mark each planned case `new` or `covered`. A plan that re-proposes fifty
existing tests is noise, and the noise is what stops it being read.

## Step 3 — Derive the cases

Four dimensions. The first is the one everybody writes; the rest are why this skill
exists.

- **Equivalence classes** — one representative per class of input that the system
  treats identically. Not one case per value.
- **Boundaries** — the edges of each class, and both sides of each edge. Off-by-one
  lives here, and it is the single highest-yield category in the list.
- **Negative paths** — invalid input, missing input, wrong type, wrong order,
  duplicate submission. What *should* fail, and fail cleanly.
- **Authorization** — the same action as the wrong role, as an unauthenticated user,
  and against another tenant's resource. Frequently the highest-severity gap, and
  the one a happy-path-only suite never touches.

Prefer **fewer, sharper cases**. Twelve well-chosen cases that a human will read beat
sixty generated permutations that nobody reviews and everybody trusts.

For each case record: `id`, `title`, `dimension`, `preconditions`, `steps`,
`expected`, `priority`, `covered` (from Step 2), and `inferred` where applicable.

## Step 4 — Emit structured output (`§T9`, `§T13`)

Emit **JSON case objects**, validated against the declared schema before they are
returned. `/test-author` consumes these directly.

Schema validation is not ceremony here: it is what makes the plan checkable the same
way whatever model produced it (`§T9`), and it turns a malformed response into a
caught error rather than a spec generated from nonsense.

Write the plan into the run manifest (`§T13`) so downstream skills read it from there
rather than being handed it — the same indirection that keeps each skill
independently runnable.

## Step 5 — Report (`§T4`)

Scrub anything published. A requirement pulled from a tracker can carry a real
customer name, an internal hostname, or a credential someone pasted into a ticket
comment — and it reaches the report with no artifact involved.

```
## Test plan — <requirement key or title>

Source:   <tracker + issue key> | pasted markdown
Coverage: <from /test-gap-finder> | not consulted — cases may duplicate existing tests

  equivalence  <n> cases   (<k> already covered)
  boundary     <n> cases
  negative     <n> cases
  authz        <n> cases

  <id>  <title>                      [new] [inferred]
  ...

Plan written to: <manifest path>
Next: /test-author generates specs from these cases

Inferred (not stated in the requirement): <ids — review these first>
Not planned: <anything deliberately out of scope, and why>
```

**Say what was inferred and what was skipped.** The inferred cases are where this
skill is most likely to be wrong, so they are the ones a reviewer should read first.

## Safety rails

- **Advises only.** Writes no spec, no fixture, no file into the repo (`§T1`).
- **Never invents scope.** A case not derivable from the requirement is marked
  `inferred`, and out-of-scope suggestions are named as such rather than folded in.
- **Never recomputes coverage** — consume `/test-gap-finder` (`§U` reuse, and a
  second heuristic is a second source of truth).
- **Tracker detected, never required** (`§A5`): the paste-in path is first-class.
- **Structured output, schema-validated** (`§T9`) — prose is not a plan.
- **Scrub anything published** (`§T4`): a ticket body is user-authored text and can
  contain anything.
- **A harness error is not a pass** (`CONVENTIONS.md §5`): no requirement, no plan,
  exit 2 in CI mode.
