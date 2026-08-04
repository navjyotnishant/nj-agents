---
name: test-report
description: "Use this skill when the user asks \"are we ready to release\", \"show test coverage against the requirements\", \"write the test report\", or wants a traceability matrix linking requirement to case to run status to defect. Reads the run manifest and the flake ledger, and reports what is covered, what is not, and what open risk a release carries. States coverage gaps rather than implying completeness. Advises only: it writes no test and makes no release decision. --html renders the same model as a self-contained page with per-spec trend sparklines from the flake ledger. Works in any git repo; nothing here is project-specific."
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

**This skill writes no test** — `§T1`'s fence has nothing to fence — and makes no
release decision: it states the position and a human decides.

Its output is a report artifact **outside the repo tree** (`NJ_AGENTS_REPORT_DIR`),
in markdown and, on `--html`, as a page. The single exception is an explicit path
argument (`--html docs/test-report.html`), which is the only way anything lands in
the repo — and then the commit is proposed, never run (`§T6`).

## Dependencies

Detected at runtime, never installed by this skill (`§T5`).

| Tool | Used for | Without it |
|---|---|---|
| the run manifest (`§T13`) | cases, specs, results | **BLOCK** — a report with no run behind it is fiction |
| `/test-plan` cases | the requirement → case half of the matrix | report spec → result only, and **say the requirement link is missing** |
| the flake ledger (`§T14`) | which passes are trustworthy | report without confidence weighting, and say so |
| `docs-designer` (this toolkit) | rendering `--html` | markdown only; say the page was not rendered |
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
║  the call. Output goes to the gitignored report dir; --html        ║
║  renders the same model as a self-contained page.                 ║
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

## Step 5a — `--html`: the same report as a page

Markdown is right for a ticket, a PR comment, or a terminal. It is wrong for the
question *"is this spec getting worse?"*, which is a shape, not a number — and the
ledger has held that shape since `nj-run ledger` started writing it.

On `--html`, render the **same model** to a self-contained page. Not a second report:
one model, two renderings. A dashboard computing its own idea of "covered" would
eventually disagree with the markdown, and then neither is trustworthy.

**Where it goes.** Default `${NJ_AGENTS_REPORT_DIR:-<repo>/.nj-agents-reports}/` —
gitignored, same as every other report artifact, so `§T1` still holds and this skill
still writes nothing into the repo tree. Only on an explicit path argument
(`--html docs/test-report.html`) does it write into the repo, and then it **proposes
the commit** rather than running git.

**What the page adds over the markdown**, and nothing else — a dashboard that merely
re-renders a table has earned no complexity:

- **Per-spec trend from the ledger** — the `recent` window as a sparkline, so a spec
  that went 0% → 15% reads differently from a steady 4%. `§T14` says trend matters
  more than magnitude; a table cannot show trend.
- **Fail rate with its denominator visible.** `18% (9/50)`, never a bare `18%` — and
  specs below the sample floor render as **"insufficient history"**, not as a rate.
  A percentage from three runs will be believed.
- **NOT COVERED first**, and visually dominant. The ordering is the whole argument of
  this report and must survive the change of medium.

**Self-contained, no exceptions.** Inline CSS, no CDN, no external fonts, no
analytics. It gets opened from a file:// path, attached to a ticket, and viewed
offline; anything fetched at load time is a broken page later, and a beacon now.
`docs-designer` already builds pages to exactly this constraint — reuse it rather
than writing a second renderer.

**Scrub before rendering** (`§T4`), not after. HTML-escape every interpolated value:
a failure message containing markup is a real input, and this page is more likely to
be attached to a ticket than any other artifact the class produces.

The verdict, the release position, and the refusal to make the call are unchanged.
A page is easier to skim than a table, which makes it easier to mistake for an
approval — so the "this is the position, not a decision" line belongs on it too,
where it will be read.

## Safety rails

- **Advises only.** Writes no test (`§T1`). Makes no release decision.
- **The report artifact is gitignored by default**, including `--html`. It lands in
  `NJ_AGENTS_REPORT_DIR`, not the repo tree. A path argument is the only way it
  writes into the repo, and then it **proposes** the commit and never runs git
  (`§T6`) — a report that commits itself is a report nobody reviewed.
- **BLOCK without a manifest.** A report with no run behind it is fiction, and this
  artifact carries more trust than any other in the class.
- **Never presents a pass rate as coverage.** They are different numbers and the
  conflation is this document's characteristic failure.
- **Never hides a broken link.** A case with no spec is the finding, not a blank row.
- **Never implies confidence a flaky pass does not support** (`§T14`).
- **Scrub everything published** (`§T4`) — this report gets pasted into tickets.
- **A harness error is not a pass** (`CONVENTIONS.md §5`).
