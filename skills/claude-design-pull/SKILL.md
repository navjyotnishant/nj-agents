---
name: claude-design-pull
description: "Use this skill when the user asks to \"match the mockup\", \"make it look like the design\", \"pull the design from Claude Design\", \"check the page against the mockup\", or wants a page held to an approved design rather than an eyeball judgement. Pulls the approved mockups from a Claude Design project into the repo, renders them alongside the running app, and compares structure and computed styles element by element — then BLOCKS while the page does not match. Advise-only: it measures and reports, never edits app code. Works in any repo with a web frontend; nothing here is project-specific."
version: 0.1.0
class: review
subclass: gate
author: navjyotnishant
---

# Claude Design Pull (review · gate)

Answers one question with evidence instead of an opinion: **does this page match
its approved design?**

This is the mirror of `/design-sync`. That skill pushes a component library **to**
Claude Design so the design agent builds with real components. This one pulls an
approved design **into** a repo and holds the running code to it.

> **Why this exists.** It was written after a session that spent ten commits
> converging on one visual direction while repeatedly reporting success. Four
> failures, all of which this skill makes impossible:
>
> 1. A page was built from *memory* of a mockup rather than the mockup — missing
>    its per-row badges, info box, and field order.
> 2. `--radius: 1.25rem` made every control resolve to 18px instead of 6px.
>    Several passes of matching by eye missed it; one dump of computed styles
>    found it immediately.
> 3. A toolbar was rebuilt while its table kept the old columns —
>    `Workflow · Nodes · Last run` against a design calling for
>    `Workflow · Last 5 runs · Last run · Repo`.
> 4. "12/12 matching" was true of twelve properties and said nothing about
>    whether the page matched. The number read as progress while the page was
>    still wrong.
>
> Each is now a case in `lib/diff.mjs`'s self-check.

> **Every skill follows `CONVENTIONS-orchestration.md` §U** — ground everything in
> the actual repo, never run git on your own initiative, no secrets in output,
> keep `CHANGELOG.md` current when the change is user-facing, degrade rather than
> fail, and say what you did not do.

This is a **review-class** skill — follow `CONVENTIONS.md` (§5 CI mode and the
exit-code contract, §6 report artifact, §7 safety rails, §8 cost control). It
**never edits application code**: it measures, reports, and blocks.

> It spawns subagents, so `§C` (cost) and `§R` (progress reporting) apply.
> **Cost shape:** one `design-parity-checker` per page, in parallel — 3 pages is
> 3 agent calls. A single page is measured inline with no agent at all. There is
> no fix loop: the skill reports and stops, so cost is bounded by page count and
> cannot escalate. State the roster before dispatch and get a yes past ~10 pages;
> halt on any signal to stop. Announce the **roster** — every page being checked
> — then mark each `✓`/`✗` with its verdict as it lands (`§R`).

> **Finding the conventions file.** It lives at the toolkit repo root, two levels
> above this skill — not beside `SKILL.md`. Skills install as symlinks, so a plain
> relative path resolves against the *link*. Resolve it first:
>
> ```bash
> ROOT="$(dirname "$(readlink -f "<this skill's base directory>")")/.."
> ```
>
> then read `$ROOT/CONVENTIONS.md`. If it is genuinely absent, say so and continue.

## Dependencies

Detected at runtime, never installed by this skill (§A5).

| Tool | Used for | Without it |
|---|---|---|
| Playwright (or a Playwright MCP) | rendering both pages and reading computed styles | **BLOCK** — there is no eyeball fallback; that is the failure mode this skill exists to prevent |
| `claude-design` MCP | `--pull` refreshing mockups from the design project | pull is skipped; the committed mockups still gate normally |

The Playwright requirement is deliberate and mirrors `/review-secrets` blocking
without a scanner. A "best effort visual check" is precisely what produced the
four failures above.

## Step 0 — State the scope and cost

Per §8: say what will be compared and what it costs **before** rendering
anything.

> "Comparing 3 pages against their mockups — renders 6 pages headless, no
> subagents. About a minute."

Then proceed. Only ask for confirmation if the run exceeds ~10 pages or the user
has asked for a full-app sweep.

## Step 1 — Locate the design source

Look for `design/manifest.json` in the repo.

- **Present** → this is a re-run. Read it, and `design/NOTES.md` if it exists;
  honour what previous runs recorded there.
- **Absent** → first run. Go to Step 2.

## Step 2 — First run: pull and author the manifest

1. **Find the design project.** Ask the user which Claude Design project holds
   the approved mockups, or take a URL. `mcp__claude-design__list_files` to see
   what is there.

2. **Pull each mockup verbatim** with `mcp__claude-design__read_file` into
   `design/mockups/<page>.html`. The bodies come HTML-entity-escaped — decode
   `&amp; &lt; &gt;` before writing.

   **Copy, never retype.** Hand-transcribing a mockup's CSS loses a pixel or two
   per element, and the accumulation is what reads as "still different". If the
   app needs the design's stylesheet, extract it with `extractStyle()` from
   `lib/pull.mjs` and copy it wholesale.

3. **Author `design/manifest.json`.** This is the one thing that cannot be
   inferred: which live element corresponds to which mockup element.

   ```json
   {
     "designProject": "<uuid>",
     "baseUrl": "http://localhost:8080",
     "pages": {
       "workflows": {
         "route": "/workflows",
         "mockup": "mockups/workflows.html",
         "pairs": [
           { "mock": ".toolbar", "live": ".sp-toolbar" },
           { "key": "chip", "mock": ".chipf", "live": ".sp-chip" }
         ],
         "sequences": [
           { "key": "columns", "mock": "th", "live": "th" }
         ],
         "require": [".sp-spark", "td:nth-child(4)"],
         "waivers": [
           { "selector": ".failure-reason",
             "reason": "WorkflowRun has no error field; it lives on RunStep",
             "tracked": "GH#14" }
         ]
       }
     }
   }
   ```

   `sequences` is the highest-value entry and the easiest to skip. Ordered text
   runs — column headers, tab labels — are what catch a page whose chrome was
   restyled while its content was left alone.

4. **Commit `design/`.** Committed mockups mean the gate runs offline and in CI,
   is reviewable in a PR, and cannot change silently when someone edits the
   design project. Propose the commit (§A3); never run git yourself.

## Step 3 — Re-runs: refresh only when asked

On `--pull`, re-fetch and reconcile with `reconcile()` from `lib/pull.mjs`.

**Report design-side changes before adopting them.** A mockup that changed means
the design moved, possibly under a page already signed off — so new failures are
attributable to a design edit rather than a code regression. Show what changed,
then ask before overwriting.

Without `--pull`, the committed mockups are used as-is. That is the normal path.

## Step 4 — Measure

Announce the roster first — the pages being checked and what each agent will do —
then dispatch. Mark each page `✓ PASS` / `✗ BLOCK` as its verdict lands, so
progress is attributable to a named page rather than a silent wait (`§R`).

**Spawn `design-parity-checker`** once per page, with that page's manifest entry
and the base URL. One agent per page keeps each verdict independently
attributable and lets pages run concurrently; the skill aggregates their findings
into the single verdict below.

For a single page, do the measurement inline rather than spawning — an agent
round-trip for one comparison is cost with no benefit (§8).

Each checker then does the following:

1. Render the mockup (`file://` the local copy) and extract facts with
   `extractorSource()` from `lib/measure.mjs`.
2. Render the live page at `baseUrl + route` and extract with the same
   extractor, live side.
3. If the live page needs a session, sign in first. A login wall renders as a
   page with none of the expected elements, which would report as dozens of
   spurious structural failures.

Both sides run through identical code, so a difference in the output is a
difference in the pages.

## Step 5 — Diff and rule

`diffPage()` then `verdict()` from `lib/diff.mjs`. Four classes:

| Class | What | Verdict |
|---|---|---|
| **structure** | missing required elements, wrong column/tab sequences, absent mapped elements | **BLOCK** |
| **style** | font-size, weight, padding, radius, border, colour on mapped pairs | **BLOCK** |
| **data-gap** | design shows a field the API cannot supply (an explicit waiver) | **WARN** — never blocks |
| **content** | real data vs mock data — names, counts, timestamps | ignored by design |

**BLOCK is the point.** There is no score and no partial credit. A page either
matches or the output is the list of what differs. Do not report "9 of 12
matching" — that framing is how a wrong page reads as progress.

**Data gaps never block**, so the gate never pressures anyone into faking data to
go green. When the design shows something the API cannot supply, the honest
resolution is an API change; the report names the missing field and moves on.

## Step 6 — Report

`renderTerminal()` for the console; `renderReport()` for the artifact at
`${NJ_AGENTS_REPORT_DIR:-<repo>/.nj-agents-reports}/design-<UTC>-<sha>.md` (§6).

Also report the colour-literal count from `countColorLiterals()`. Not a gate — a
drift meter. Every hardcoded hex is a place the design can diverge unnoticed;
a jump between runs is worth seeing in review.

Record anything learned — a selector that needed changing, a page that needs a
login, a genuine data gap — in `design/NOTES.md` so the next run does not
rediscover it.

## Step 7 — Fixing is a separate act

This skill measures. It does not edit application code.

Hand the deltas back and let the user decide, or fix them in a separate pass and
re-run the gate. That separation is what keeps the verdict trustworthy: a gate
that fixes its own failures cannot tell you whether it ever failed.

## CI mode

`NJ_AGENTS_CI=1` or `--ci`: never prompt, never `--pull`, resolve ambiguity to
the safe outcome. Exit `0` on PASS/WARN, `1` on BLOCK (§5).

Because the mockups are committed, the gate runs in CI with no MCP connection —
which is the point of keeping them in the repo.

## Self-checks

Every module carries an assert-based check with no framework:

```bash
for f in measure diff pull report; do node lib/$f.mjs --self-check; done
```

Plus a regression suite that replays real failures this gate exists to catch:

```bash
node lib/known-bad.test.mjs
```

Every case in it is a state the code was actually in — and was reported as "done"
at the time. If those stop blocking, the gate has lost the ability to catch the
mistakes it was built for, and the skill is decorative.
