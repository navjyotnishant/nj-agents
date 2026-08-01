---
name: test-report
description: "Use this skill when the user asks \"are we ready to release\", \"show test coverage against the requirements\", \"write the test report\", or wants a traceability matrix linking requirement to case to run status to defect. Reads the run manifest and the flake ledger, and reports what is covered, what is not, and what open risk a release carries. States coverage gaps rather than implying completeness. Advises only: it writes no test and makes no release decision. Works in any git repo; nothing here is project-specific."
version: 0.1.0
class: testing
author: navjyotnishant
---

# Test Report (testing)

The traceability matrix: **requirement → case → spec → run status → defect**, plus an
honest statement of what a release would be carrying.

This is the artifact someone shows a stakeholder, which is exactly why its failure
mode is dangerous. A report that lists what passed, and stops, reads as *"we tested
this"* — when the useful information is usually what was never tested at all.

**Coverage gaps are the headline, not a footnote.**

This is a **testing-class** skill — follow `CONVENTIONS-testing.md`: `§T4` scrub
anything published, `§T13` read the manifest, `§T14` read the flake ledger.

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

**This skill is read-only.** It writes no test and no repo file — `§T1`'s fence has
nothing to fence. Its output is a report artifact outside the repo tree, and it makes
no release decision: it states the position and a human decides.

## Dependencies

Detected at runtime, never installed by this skill (`§T5`).

| Tool | Used for | Without it |
|---|---|---|
| the run manifest (`§T13`) | cases, specs, results | **BLOCK** — a report with no run behind it is fiction |
| `/test-plan` cases | the requirement → case half of the matrix | report spec → result only, and **say the requirement link is missing** |
| the flake ledger (`§T14`) | which passes are trustworthy | report without confidence weighting, and say so |
| a connected tracker (MCP) | linking defects by key | list defects inline; paste-ready (`§A5`) |

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  TEST REPORT — TESTING                                            ║
╠══════════════════════════════════════════════════════════════════╣
║  Traceability: requirement → case → spec → status → defect.       ║
║  Leads with what is NOT covered, because a report that only       ║
║  lists passes reads as "we tested this".                          ║
║                                                                   ║
║  ADVISES ONLY. It states the release position; it does not make   ║
║  the call, and it writes nothing into your repo.                  ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **A run manifest** (`§T13`). Absent → BLOCK: a report with no run behind it is
  fiction, and this is the artifact people trust most.
- **Ideally case objects** from `/test-plan`. Absent → the requirement column cannot
  be filled; say so rather than leaving it blank and implying coverage.

## Step 1 — Build the matrix (`§T13`)

Join what already exists. Every link is read, none inferred:

| Column | Source |
|---|---|
| requirement | `/test-plan` case objects (their `id` and origin) |
| case | the same objects |
| spec | `/test-author`'s generated spec carrying the case `id` |
| status | the run manifest |
| defect | `/test-triage`'s classification and any filed ticket |

**A broken link is the finding.** A case with no spec is untested. A spec with no
case is coverage nobody planned — worth knowing, not necessarily wrong. Report both
rather than dropping the row.

## Step 2 — Lead with the gaps

Order the report by what is missing, not by what passed:

- **Requirements with no case** — nobody planned to test this.
- **Cases with no spec** — planned, never written.
- **Specs that never ran** — skipped, filtered, or the shard did not complete.
- **Specs quarantined** — coverage deliberately suspended; name the SLA (`§T14`).

> **A pass rate is not coverage.** "98% passing" says nothing about whether the
> untested 40% of the requirement would have passed. The two get conflated in
> exactly this document, and the conflation is what turns a test report into
> reassurance.

## Step 3 — Weight passes by confidence (`§T14`)

A pass from a spec that fails 20% of the time is weaker evidence than a pass from a
spec that has never failed. Read the ledger and say which passes are load-bearing.

This matters most for release readiness: a green run whose green depends on three
known-flaky specs is not the same result as a green run that does not.

## Step 4 — State the release position, do not decide it

Summarise what shipping now would carry:

- open real defects, by severity
- coverage gaps, by requirement
- quarantined specs and their SLAs
- passes resting on flaky specs

Then **stop.** Whether that is acceptable is a business call with context this skill
does not have — a known defect in an unreleased feature flag is not the same as one
on the login path. Stating the position is useful; making the call is overreach.

## Step 5 — Report (`§T4`)

Scrub everything published. This report carries failure messages and request URLs
from a real session, and it is the document most likely to be pasted into a ticket or
a chat channel.

```
## Test report — <scope>          Verdict: <from /e2e-suite>

Run: <manifest>   Environment: <url>   Ledger: <n> specs with history

  NOT COVERED
    <requirement>          no case planned
    <case id>              planned, no spec
    <spec>                 never ran — <why>
    <spec>                 quarantined — SLA <date>

  COVERED
    requirement    case      spec              status   defect
    <req>          <id>      <file>            pass
    <req>          <id>      <file>            FAIL     <key> real defect
    <req>          <id>      <file>            pass*    * spec fails 18% of runs

  RELEASE POSITION
    open defects:    <n>  (<severity breakdown>)
    coverage gaps:   <n> requirements untested
    quarantined:     <n> specs, earliest SLA <date>
    weak passes:     <n> resting on specs with >10% fail rate

  This is the position, not a decision. Shipping is your call.

Not in this report: <what could not be linked, and why>
```

## Safety rails

- **Advises only.** Writes no test, no repo file (`§T1`). Makes no release decision.
- **BLOCK without a manifest.** A report with no run behind it is fiction, and this
  artifact carries more trust than any other in the class.
- **Never presents a pass rate as coverage.** They are different numbers and the
  conflation is this document's characteristic failure.
- **Never hides a broken link.** A case with no spec is the finding, not a blank row.
- **Never implies confidence a flaky pass does not support** (`§T14`).
- **Scrub everything published** (`§T4`) — this report gets pasted into tickets.
- **A harness error is not a pass** (`CONVENTIONS.md §5`).
