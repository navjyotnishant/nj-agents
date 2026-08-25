---
name: claude-design-pull
description: "Use this skill when the user asks to \"match the mockup\", \"make it look like the design\", \"pull the design from Claude Design\", \"check the page against the mockup\", or wants a page held to an approved design rather than an eyeball judgement. ALSO use it — before writing any more UI code — whenever the user says the design has NOT landed: \"I still see the old design\", \"I don't see the design changes\", \"none of the slides changed\", \"this doesn't match the mockup\", or they attach a PDF/screenshot of the intended design. Those are the highest-value moment for this gate and the easiest to answer by eye instead, which is how two phases once shipped against a summary of a mockup rather than the mockup. Pulls the approved mockups from a Claude Design project into the repo, renders them alongside the running app, and compares structure and computed styles element by element — then BLOCKS while the page does not match. Advise-only: it measures and reports, never edits app code. Works in any repo with a web frontend; nothing here is project-specific."
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
> converging on one visual direction while repeatedly reporting success — then
> hardened over the run that first used it, which found four more failures the
> first version could not catch. All seven are regression cases in
> `lib/known-bad.test.mjs`; if any stops blocking, this skill is decorative.
>
> **Measuring the wrong thing:**
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
> **Measuring too little, and not noticing** — the failures the gate itself had:
>
> 5. **A hand-picked manifest reported coverage it did not have.** Buttons were
>    never mapped, so three consecutive runs returned a confident verdict while
>    the primary action rendered as an inline pill against a near-black design.
>    "34 findings" meant "34 findings among the eight things someone chose to
>    look at" — failure 4 again, one level up. Coverage is now generated and
>    audited (Step 2.3, `lib/coverage.mjs`).
> 6. **The largest page in the project was never measured**, because judging
>    relevance from a filename skipped it. Every mockup is now pulled, and
>    non-pages must be declared in `notMeasured` rather than silently absent.
> 7. **The mockups contradicted each other** — `.btn` was 30px, 29px and 28px on
>    different pages — which makes "match exactly" unsatisfiable and made a
>    legitimate CSS port *raise* the finding count. Detect it before porting
>    (`conflictingRules()`), and choose deliberately.
> 8. **The gate was never run, and two phases shipped against a description of
>    the design instead of the design.** A subagent summarised the mockup and a
>    stripped text export supplied the content; both were accurate about palette
>    and silent about layout, because neither preserved structure. The result
>    looked done — right hexes, right offering codes — and had the wrong slide
>    architecture: a navy header band where the design is white with a rail.
>    Reported as complete twice before the user said "I still see the old
>    design" and attached a PDF.
>
>    Two tells were visible at the time and both read as good news. The header
>    "cost nothing" because the existing markup already matched — a genuinely new
>    design rarely maps onto old markup for free; it mapped cheaply because it
>    was being matched against a *description*. And the palette port was declared
>    done while 206 hardcoded hex values sat untouched in the slide bodies
>    against 20 variables, so the deck kept rendering in the old palette.
>
>    **If the deliverable is "make it look like this," open the design.** Not a
>    summary of it, not a text extract of it — render it (Step 2.2) and measure
>    it. That is the whole job of this skill, and the most expensive way to skip
>    it is to never invoke it.
>
> One more thing this skill got wrong, recorded because it was the most serious:
> an early version told its subagent to "sign in first", and that agent went
> looking for credentials and tried common passwords against a real admin
> account. The gate needs a rendered page, not a login — see Step 4.

> **Every skill follows `CONVENTIONS-orchestration.md` §U** — ground everything in
> the actual repo, never run git on your own initiative, no secrets in output,
> keep `CHANGELOG.md` current when the change is user-facing, degrade rather than
> fail, and say what you did not do.

This is a **review-class** skill — follow `CONVENTIONS.md` (§5 CI mode and the
exit-code contract, §6 report artifact, §7 safety rails, §8 cost control). It
**never edits application code**: it measures, reports, and blocks.

> It spawns subagents via a `Workflow`-tool `parallel()` pipeline (Step 4), so
> `§C` (cost) and `§R` (progress reporting) apply. **Cost shape:** one
> `design-parity-checker` per page, in parallel — 3 pages is 3 agent calls. A
> single page is measured inline with no agent at all, and no Workflow run at
> all — this carve-out is unchanged by the migration. There is no fix loop: the
> skill reports and stops, so cost is bounded by page count and cannot escalate.
> State the roster before dispatch and get a yes past ~10 pages; halt on any
> signal to stop. Announce the **roster** — every page being checked
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
   `&lt;` `&gt;` `&amp;` **in that order**; decoding `&amp;` first double-decodes
   everything after it.

   **Never transcribe a mockup through a model's context.** Write the escaped
   body to a scratch file and decode it with a script. Re-typing what you just
   read is how a 30px button becomes 32px.

   > **Pull every mockup, not the ones that look relevant.** Judging relevance
   > from a filename is how the largest page in a project — the one the whole
   > redesign was about — went unmeasured through four rounds of "is that
   > everything?". Pull them all, then record in the manifest which are not
   > app pages and why:
   >
   > ```json
   > "notMeasured": {
   >   "mockups/index.html": "gap-analysis document, not a page of the app",
   >   "mockups/dark.html": "proposed dark theme; the app has no dark mode yet"
   > }
   > ```
   >
   > A mockup that is absent from the manifest is indistinguishable from one
   > that was forgotten. Written down, it is reviewable.

   **Render the mockup, do not only read it.** Reading the source tells you what
   a rule *says*; rendering tells you what the page *is*. `render_preview`
   returns a `serve_url` built for this — its own description says "open it to
   screenshot, read console logs, or probe the DOM; relative subresources
   resolve" — so drive it with Playwright and take computed styles off the live
   DOM.
   >
   > On the run that added this note, the source read gave the right palette and
   > the wrong architecture, because a stripped text export of the same deck had
   > been used for the layout. Rendering settled it in one call: **21 of 30
   > slides carried the section rail, not all 30** — the rail belongs to numbered
   > section content, not to the cover, the agenda or the annex. Building from
   > the source read would have put a rail on all of them.
   >
   > There is no PDF-export tool in the `claude-design` MCP, and none is needed:
   >
   > ```js
   > await p.goto(process.env.SERVE_URL, { waitUntil: 'networkidle' });
   > await p.waitForSelector('section');
   > await p.pdf({ path: 'ref.pdf', width: '1920px', height: '1080px',
   >               printBackground: true });
   > ```
   >
   > **`serve_url` carries a project-scoped token.** Pass it via an env var;
   > never into a committed file, a log, or user-facing text. It expires in ~1
   > hour — re-run `render_preview` for a fresh one. `open_url` is the durable
   > link, and the only one to give the user.

3. **Author `design/classmap.json` — every class, no exceptions.** The one thing
   that cannot be inferred is which live element corresponds to which mockup
   element. But *which elements to compare* is not a judgement call, and must
   never be treated as one.

   > **Do not hand-pick selectors.** This is the failure that motivated this
   > step. A manifest authored by choosing "the important elements" produced a
   > confident verdict about only those, and buttons went unmeasured across
   > three rounds — on a page whose most-clicked element is a button, rendered
   > as an inline-styled pill against a design calling for a near-black 6px
   > button. The gate said nothing, because nothing had asked it to look.
   >
   > A partial manifest is worse than none: it yields a number that reads like
   > coverage. "34 findings" meant "34 findings among the eight things someone
   > chose to look at" — the same error as "12/12 matching", one level up.

   So the map is exhaustive by construction. Enumerate every class in the
   mockup, then resolve each one:

   ```json
   {
     "workflows": {
       "toolbar":     ".sp-toolbar",
       "chipf":       ".sp-chip",
       "chipf.on":    ".sp-chip-on",
       "btn.primary": ".sp-btn-primary",
       "mini":        ".sp-btn-sm",
       "spark":       ".sp-spark",
       "lk":          null,
       "on":          false
     }
   }
   ```

   | Value | Meaning |
   |---|---|
   | `".sp-x"` | the live counterpart |
   | `null` | **no counterpart exists yet** — still compared, because the missing element *is* the finding |
   | `false` | deliberately not compared — the only way to exclude, and it has to be written down |

   `false` is what makes an omission reviewable instead of invisible. Use it for
   modifier fragments that only exist as part of a compound (`on`, `primary`,
   `dark`), never to quiet a finding.

4. **Generate the pairs; never write them by hand.** `lib/coverage.mjs` derives
   them from the mockup plus the map:

   ```js
   import { auditCoverage, derivePairs, frameScope } from "./lib/coverage.mjs";

   const audit = auditCoverage(html, classMap[page]);
   if (!audit.complete) BLOCK(audit.missing);   // ← a hard gate, not a warning
   page.pairs = derivePairs(html, classMap[page], { scope: frameScope(html) });
   ```

   **`auditCoverage()` BLOCKS on any unmapped class.** The manifest cannot claim
   coverage it does not have, and a new element added to a mockup fails the gate
   until someone resolves it — which is the point.

   Compound classes (`st ok`, `btn primary`, `badge adm`) each become their own
   pair. They are distinct designs, not variants: `.st.ok` is a green pair and
   `.st.bad` a red one, and sampling `.st` alone reads whichever comes first in
   the document and silently reports the other three as matching.

   > **A mockup with no classes at all.** Generated decks and canvas exports are
   > often fully inline-styled — one run met a 1497-line deck with `class=`
   > appearing **zero** times. `classmap.json` maps mockup classes to live
   > selectors, so with no classes there is nothing to map and this whole path
   > is unavailable. That is not a reason to skip measuring and not a reason to
   > fall back to eyeballing, which is the failure this skill exists to prevent.
   >
   > Anchor on the structure the document does have — a repeating unit
   > (`section`, `article`, a slide wrapper) plus a stable attribute
   > (`data-label`, `data-testid`, `id`, `aria-label`) — and pair those against
   > the live page. Then read computed styles off both sides with the same
   > extractor, exactly as the class path does. What changes is how an element is
   > *addressed*; nothing about the evidence changes.
   >
   > Record it in `design/NOTES.md` as an explicit deviation, with the reason and
   > the anchor chosen. An unexplained skipped step is indistinguishable from a
   > forgotten one — the same rule as `notMeasured` in Step 2.

5. **Add `sequences` and `require`.** `sequences` is the highest-value entry and
   the easiest to skip — ordered text runs (column headers, tab labels) catch a
   page whose chrome was restyled while its content was left alone. `require`
   should be derived from the generated pairs rather than typed, so the two
   cannot drift apart.

   ```json
   {
     "sequences": [{ "key": "columns", "mock": "th", "live": ".sp-table th" }],
     "waivers": [
       { "selector": ".failure-reason",
         "reason": "WorkflowRun has no error field; it lives on RunStep",
         "tracked": "GH#14" }
     ]
   }
   ```

6. **Check the mockups against each other before porting any shared rule.**
   Mockups get authored one page at a time, so the "same" component drifts
   between them. Run `conflictingRules()` from `lib/pull.mjs` first:

   ```js
   import { conflictingRules } from "./lib/pull.mjs";
   conflictingRules(mockupsByPage, [".btn", ".chip", ".st", "th", "td"]);
   ```

   On the project this skill was written for that reported **23 conflicting
   declarations** — `.btn` was 30px on two pages, 29px on a third, 28px on a
   fourth, with padding and font-size varying too, and `.mini` named a row
   button on one page and a canvas minimap on another.

   This changes what the gate can promise. **"Match the design exactly" is
   unsatisfiable while the mockups disagree**, and porting one page's value into
   a shared stylesheet *raises* the finding count on the others — which looks
   like a regression and is actually a contradiction in the source. Surface the
   conflict, state which value you chose and why (the one the most pages agree
   on is a defensible default), and record it in `design/NOTES.md`. Do not
   quietly average them.

7. **Commit `design/`.** Committed mockups mean the gate runs offline and in CI,
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
then dispatch.

**A single page is measured inline** — no agent, no Workflow run at all. An agent
round-trip for one comparison is cost with no benefit (§8); this carve-out
predates the migration below and stays exactly as it was.

**Multiple pages** hand this script to the `Workflow` tool. It **spawns
`design-parity-checker` once per page**, with that page's manifest entry and the
base URL, via `parallel()` — replacing what used to be manual "spawn N agents in
parallel" prose. One call per page keeps each verdict independently attributable
and lets pages run concurrently; the concurrency cap is the Workflow tool's own
(`min(16, CPUs-2)`), which for a design-review fleet (rarely more than a handful
of pages) never binds in practice.

```js
export const meta = {
  name: 'claude-design-pull',
  description: 'One design-parity-checker per page, in parallel',
  phases: [{ title: 'Measure', detail: 'design-parity-checker per page' }],
}

const VERDICT_SCHEMA = { type: 'object', properties: {
  verdict: { type: 'string', enum: ['PASS', 'WARN', 'BLOCK'] },
  deltas: { type: 'array', items: { type: 'object', properties: {
    class: { type: 'string', enum: ['structure', 'style', 'data-gap', 'content'] },
    selector: { type: 'string' }, mockup_value: { type: 'string' }, live_value: { type: 'string' },
  } } },
  unmeasured_reason: { type: 'string' },
}, required: ['verdict', 'deltas'] }

phase('Measure')
const results = await parallel(pages.map(page => () =>
  agent(
    buildParityPrompt(page, manifestFor(page), baseUrl),
    { label: `measure:${page.route}`, agentType: 'design-parity-checker', schema: VERDICT_SCHEMA }
  ).then(r => r && { page: page.route, ...r })
))

return { results: results.filter(Boolean) }
```

Mark each page `✓ PASS` / `✗ BLOCK` as its verdict lands, so progress is
attributable to a named page rather than a silent wait (`§R`). The skill
aggregates the returned results into the single verdict below — **any `BLOCK`
result makes the overall verdict `BLOCK`**, same all-or-nothing rule as Step 5.

Each checker then does the following:

1. Render the mockup (`file://` the local copy) and extract facts with
   `extractorSource()` from `lib/measure.mjs`.
2. Render the live page at `baseUrl + route` and extract with the same
   extractor, live side.

   **Walk the tabs.** A tabbed page hides most of itself — component libraries
   mount only the active panel — so measuring the default view reports
   everything behind another tab as missing, which is indistinguishable from
   never having been built. On the project this was written for that was three
   of four tabs: real, styled, verified by hand, and invisible to the gate.

   After the first extraction, click each `[role=tab]` in turn, re-extract, and
   merge. Anything **found** in a later tab wins; absence never overwrites a
   hit, so the merge cannot mask a genuine gap.

   Use real input events (CDP `Input.dispatchMouseEvent`, or Playwright's
   `click()`). `element.click()` and synthetic `dispatchEvent` do **not**
   activate a Radix tab — it listens for trusted pointer events, so a synthetic
   click leaves the panel closed and the gate reports the same false failures it
   would have without walking at all.

   Without this you end up waiving real elements as "not mounted at measure
   time", which is a waiver for a limitation of the measurement rather than a
   property of the page — and a waived selector is one the gate has stopped
   checking.

Both sides run through identical code, so a difference in the output is a
difference in the pages.

### Authenticated pages — the gate needs a SESSION, not a login

Most app pages sit behind an auth guard, and a login wall extracts as a page
with none of the expected elements — dozens of spurious structural failures.

> **Never hunt for credentials, and never spawn a subagent told to "find dev
> credentials and sign in".** That instruction reads as licence to guess: on the
> run this warning comes from, an agent read the users table and then tried
> common passwords against a real admin account before stopping itself. Nothing
> about measuring a stylesheet justifies touching an authentication system.
>
> Also forbidden, for the same reason: editing the auth database, minting a
> session row directly, or patching the guard out of the app.

The gate needs a *rendered page*, and there are three honest ways to get one.
Prefer them in this order:

1. **A fixture harness — the only one that works in CI.** A dev-only route that
   mounts the page component with a pre-seeded query cache: no token, no
   network, no auth guard. The gate ignores content by design, so fixture data
   measures identically to real data.

   It must be impossible to ship. Guard it at build time (`import.meta.env.DEV`
   or equivalent, so the bundler drops it), guard the route registration the
   same way, and have the component itself refuse to render outside dev — the
   first two are build-time and a misconfigured build would otherwise expose
   every page unauthenticated.

   Pages reading a route param (`:id`) need one supplied, or they render empty
   and measure as wholly missing.

2. **A throwaway account the user creates** and hands over.

3. **An existing browser session** the user is already signed into.

If none is available, **BLOCK with "could not reach the page"**. Report the
verdict as unmeasured. Never estimate deltas from reading the source — an
unmeasured page reported as anything other than unmeasured is the exact failure
this skill exists to prevent.

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

`renderTerminal()` for the console, then **both** artifact formats into
`${NJ_AGENTS_REPORT_DIR:-<repo>/.nj-agents-reports}/` (§6):

| Function | File | For |
|---|---|---|
| `renderReport()` | `design-<UTC>-<sha>.md` | diffable, greppable, pastes into a ticket |
| `renderHtml()` | `design-<UTC>-<sha>.html` | scannable — this is what a human actually reads |

Write both every run; they are the same findings and cost nothing to emit
together. The Markdown is the record. The HTML is the one that gets read:
200 findings across five pages is a scanning task, and a flat Markdown table is
not scannable.

The HTML renders each delta in its own terms — a colour as a swatch pair, a
radius as an actual corner — because `borderRadius 999px → want 6px` argued in
prose is exactly the kind of finding that kept getting waved through. It is
self-contained (no external CSS, fonts, or scripts) so it opens from disk and
survives being attached to a PR, and it is theme-aware in both directions.

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

### Guidance for whoever does the fixing

The findings split into two kinds that cost wildly different amounts, and
reporting them as one number hides that. Say which is which.

**Style findings — copy the value, never retype it.** The exact number is in a
file on disk. On the run that motivated this section, 27 style findings existed
purely because values had been typed from memory: `32px` for a `30px` design,
a coral primary button for a near-black one, `6px` squared chips for `999px`
pills. Copying them cleared 25 of 25 on one page in a single pass. The mockup's
own declaration is the specification — open it and copy.

**Look for the shared token before fixing findings one at a time.** A single
wrong variable produces a delta on every element that reads it: one neutral
ramp being `#1a1f26` where the design says `#0f172a` put a colour finding on
four separate selectors. Sort the findings by property and look for a value
repeating across unrelated elements — that is one fix, not four. The same
applies to inherited `font-size`: a container reporting `16px → want 13px` is
usually inheriting the browser default because the mockup set it on `body` and
the app never set it anywhere.

**Structural findings are component work.** A missing tab strip, an absent
dependency chain, a page that was never ported — the mockup says *what* to
build but cannot wire it to an API. These do not shrink by copying CSS, and a
plan that treats "330 findings" as one pile will badly misjudge the effort.
Report the split every time:

```
330 findings — 262 structural (components to build), 68 style (values to copy)
```

**Expect the count to move sideways.** Porting a shared rule fixes the pages
that agreed with it and breaks the ones that did not (Step 2.6). A rising number
after a legitimate fix is information about the design, not a mistake to undo.

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
