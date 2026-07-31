---
name: arch-diagram
description: Use this skill when the user asks to "generate an architecture diagram", "draw the system architecture", "create a solution/deployment/data-flow/sequence/ER diagram", or wants a visual of how the project fits together. Reads the project's README, architecture docs, and ADRs first to ground the diagram, then authors a presentation-quality SVG directly — infographic style by default, --sketch for a hand-drawn variant — places it into the project docs, and PROPOSES the commit. Every diagram is rendered and looked at before it ships. Works in any git repo; nothing here is project-specific.
version: 0.4.0
class: authoring
author: navjyotnishant
---

# Architecture Diagram (authoring)

Generates a **system / solution / sequence / data-flow / deployment / ER** diagram,
grounded in the project's own docs, and places it into the documentation. It
**writes the files** but only **proposes** the commit.

The diagram is **authored directly as SVG** — laid out deliberately rather than
emitted from a fixed grid. That is what makes gradients, badges, hexagons, a legend
and a takeaway row possible, and what lets a layout be *rearranged* when it reads
badly instead of being stuck with whatever a renderer produced.

This is an **authoring-class** skill — follow `CONVENTIONS-authoring.md` (repo
ingest §A1, scoped output §A2, propose-commit §A3, placement §A4, MCP-detect §A5,
grounding/safety §A6, non-clobber §A7).

> **Finding the conventions file.** It lives at the toolkit repo root, two levels
> above this skill — not beside `SKILL.md`. Skills are usually installed as
> symlinks into your runner's skills directory, so a plain relative path resolves against the
> *link* and misses it. Resolve the link first:
>
> ```bash
> ROOT="$(dirname "$(readlink -f "<this skill's base directory>")")/.."
> ```
>
> then read `$ROOT/CONVENTIONS-authoring.md` and `$ROOT/CONVENTIONS.md`. If a file is genuinely absent, say so and continue
> with the procedure below rather than stopping.

> **Every skill follows `CONVENTIONS-orchestration.md` §U** — ground everything in
> the actual repo, never run git on your own initiative, no secrets in output,
> keep `CHANGELOG.md` current when the change is user-facing, degrade rather than
> fail, and say what you did not do.

> **Spawning subagents — `CONVENTIONS-orchestration.md`.** This skill spawns agents,
> so `§C` (cost) and `§R` (progress reporting) apply. **Cost shape:** 0–1 agent calls
> — the diagram is normally authored inline, and `diagram-architect` is spawned only
> for a large or unfamiliar system. State it and get a yes before any dispatch; cap
> fix rounds at 2; halt on any signal to stop. Announce each stage as it starts and
> report the **round against the cap** (`round 2/2`) so the loop shows its bound.


## Dependencies

Detected at runtime, never installed by this skill (`§A5`).

| Tool | Used for | Without it |
|---|---|---|
| `rsvg-convert` (graphviz/cairo) | rasterising the SVG so it can be looked at | the visual pass is skipped — say so rather than implying it ran |

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  ARCHITECTURE DIAGRAM — AUTHORING                                ║
╠══════════════════════════════════════════════════════════════════╣
║  Reads your project + architecture docs, then authors a          ║
║  presentation-quality SVG (infographic by default, --sketch for  ║
║  hand-drawn) and places it in your docs. It renders and LOOKS    ║
║  at the result, critiques it, and fixes it before shipping.      ║
║  It writes the diagram, then PROPOSES the commit — never git.    ║
║  Everything is grounded in your repo; nothing is invented.       ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **Something to read** — README / `docs/` / `ARCHITECTURE.md` / ADRs, or source to
  skim. If the repo is essentially empty, say there's not enough to diagram and stop.
- **No tooling required to author.** An SVG rasterizer (`rsvg-convert`, ships with
  graphviz/cairo) is used to *look* at the result in Step 5 — without one, say the
  visual pass was skipped rather than implying it ran.

## Step 1 — Resolve type, mode, and style

- **Type:** `system-arch` (default), `solution-arch`, `sequence`, `data-flow`,
  `deployment`, `er`. Ask if unclear.
- **Mode** — `structural` (boxes are real repo components; full §A6 grounding) or
  `conceptual` (boxes are ideas — a trust boundary, a request lifecycle). In
  conceptual mode the facts must still be true, but a node need not map 1:1 to a
  file. Resolve this explicitly: a concept drawn structurally fights its own intent.
- **Style:**
  - **`infographic` — the DEFAULT.** Clean gradients, system font, crisp connectors.
    Presentation material. Use it unless asked otherwise.
  - **`--sketch`** — same layout, hand-drawn finish: flat paper fills, a handwriting
    font, a subtle wobble on card borders.

  Both are authored the same way, and `--sketch` changes only the finish — so the
  layout never needs re-validating when switching between them.

  > **Sketch gotcha:** a displacement filter applied to a `<path>` **suppresses its
  > arrowheads** — SVG markers are not rendered through a filter. Wobble the *cards*,
  > never the connectors, or every arrow silently loses its head.

- **Other formats on request:** mermaid (renders natively in Markdown, good for a
  simple graph), draw.io, or Figma-via-MCP (§A5). Opt-in, never defaults.

### Cheap path first (cost control)

**Author the diagram inline.** For anything under ~20 nodes, or any system already
understood from the repo ingest, write the SVG yourself — do not spawn
`diagram-architect`. It earns its cost on a large or unfamiliar system, not on a
five-box flow. Say the cost shape before spawning anything.

## Step 2 — Ingest the architecture docs

Per `CONVENTIONS-authoring.md §A1`, architecture-focused: read `README*`,
`ARCHITECTURE.md`, everything under `docs/` (esp. `docs/architecture/`, `docs/adr/`),
design docs, and skim source **entry points** and top-level module layout. Note what
you did and didn't read.

## Step 3 — Design the visualization BEFORE drawing

Do not start emitting shapes. Decide, in order:

1. **The one thing it must say.** Write the headline first — the outcome, not the
   machinery. *"A repo in. A publish-ready post out."* beats *"the tech-blog
   pipeline."* If you can't state it in a sentence, you don't understand the system
   well enough to draw it yet.
2. **Layout.** Strictly **left → right** or **top → bottom**. Never both.
3. **Grouping.** More than ~6 items: group them into phases and label the bands. Nine
   agents drawn as nine boxes is machinery; nine agents in four phases is a story.
4. **Shapes and colour** — see the visual language below.
5. **Callouts** — what deserves emphasis: the gate, the failure path, the output.
6. **A legend**, whenever more than one shape or line style carries meaning.
7. **A takeaway row** — two or three numbers that survive after the picture fades.

**Then, before drawing a single shape, resolve these — they are the failures the
render pass keeps catching, and every one is avoidable up front:**

- **Count first, draw second.** Get every number from the repo *before* laying out.
  If a band says 15, draw 15 shapes. A count that disagrees with the shapes beside it
  is the most visible error a diagram can carry, and it is pure carelessness.
- **Reserve the space each element needs.** A card's tallest text decides its height;
  a label's length decides its width. Deciding this after placement is what produces
  clipped text and labels sitting on frame strokes.
- **Route the connectors before placing the boxes.** If an arrow would cross another
  or pass through a label's space, move the box now — rerouting later never works.
- **Fill the canvas or shrink it.** Large empty regions are not whitespace, they are
  an unfinished layout. Size the viewBox to the content.
- **Decide what earns emphasis.** Exactly one element should be the most prominent.
  If everything is emphasised, nothing is.

### Visual language

| | |
|---|---|
| **Rounded rectangle** | a service, stage, or phase |
| **Hexagon** | an AI agent |
| **Cylinder** | a database |
| **Cloud** | a SaaS / external platform |
| Blue | user-facing systems |
| Green | **success · pass · output** |
| Orange | AI agents and their work |
| Purple | databases |
| Grey | neutral inputs, external systems |
| **Red** | **failure · blocked · stopped** |
| Solid arrow | synchronous |
| Dashed arrow | asynchronous |

**Red and green are reserved.** They mean failure and success — never "internal
service" or any other category. Never colour a failure green or a success red: that
inversion is the single most misleading thing a diagram can do.

**Only use a shape that has something to represent.** A legend listing cylinders and
clouds on a diagram with no database and no SaaS is noise.

### Layout rules

- **No crossing arrows.** If two cross, move a node — don't route around it.
- **Never a spaghetti diagram.** If it looks like one, the grouping is wrong.
- Subtle shadows, generous whitespace, no clutter.
- Support light *and* dark via `prefers-color-scheme` in a `<style>` block.
- Wrap it in the house frame — a hand-drawn border, drawn first so nothing overlaps.

## Step 4 — Author the SVG

Write the SVG directly. For a system too large or unfamiliar to hold in your head,
spawn `diagram-architect` for the structured model first, then author from it.

Everything traces to the repo (§A6) — no invented components. If a **count** appears
in the diagram, verify it against the repo: a wrong number in the most glanceable
part of a graphic is worse than no number at all.

## Step 5 — Render → LOOK → critique → fix (MANDATORY)

**A diagram is not done when the file is written. It is done when you have looked at
it and it passes.** Source review cannot see legibility; only rendering it can.

```bash
rsvg-convert -w 1400 docs/architecture/<name>.svg -o /tmp/<name>.png
```

Then **view the PNG** and critique it as a UX designer would:

> **Would an executive understand this in 15 seconds?**
>
> - Does the headline state the outcome, or merely name the system?
> - Can they tell what it produces, and what it prevents?
> - Is the most important element also the most visually prominent?
> - Do any arrows cross? Any text clipped, overlapping, or truncated mid-word?
> - Is every number in it actually correct?

**A finding here that Step 3 should have prevented — a wrong count, a clipped
label, dead space — is a process failure, not a QA success.** Fix it, and fix the
habit: those belong in the design pass. What this step legitimately catches is what
source review cannot see: text rendered behind a stroke, arrowheads suppressed by a
filter, glyphs that fall back to tofu.

If the answer is no, **redesign** — don't tweak. Rearrange the layout, re-group, cut
nodes. Repeat until it passes, **capped at 2 fix rounds**.

**At the cap, stop and ask — don't decide alone.** Report what's fixed, what still
fails, and whether the remainder is cosmetic or misleading. Then offer the choice:

```
Round 2/2 done. Fixed: <…>. Still open: <…>.
Ship as-is, or run 2 more rounds?
```

Two more rounds only on a yes. The cap exists so spend is a decision, not a
side-effect — and the answer is often "ship it", because a diagram that reads
correctly with a cosmetic flaw beats one polished at ten times the cost.

Real failures caught this way that no geometry check would have found: a group label
rendered *behind* its own frame stroke; an agent count that said 7 when it was 9;
arrowheads silently removed by a filter; a label clipped so "post" read as "ost".

Clean up scratch PNGs — they never belong in the repo.

## Step 6 — Resolve placement and embed

Per `CONVENTIONS-authoring.md §A4`:
1. An existing `ARCHITECTURE.md` or `docs/architecture/`.
2. Else a README "Architecture" section.
3. Else a new `docs/architecture/<type>.md`.

Write `docs/architecture/<type>.svg` and embed with
`![<type> architecture](./<type>.svg)`. SVG renders on GitHub and scales cleanly, so
no raster is needed unless asked. Update in place on re-run; keep filenames stable so
doc links don't break (§A7).

## Step 7 — Summary + propose commit

Say what the diagram shows, which type/style, where it landed, and **what it does not
show** — a diagram that implies more coverage than it has is worse than none. If the
visual pass was skipped for want of a rasterizer, say so plainly.

Then propose the commit per `CONVENTIONS-authoring.md §A3`:

```bash
git add docs/architecture/<type>.svg <edited-doc>
git commit -m "docs: add <type> architecture diagram"
```

Never run git. Add a validation note: open the SVG on GitHub to confirm it reads
correctly before pushing.

## Safety rails

- **Look at every diagram before shipping it** (Step 5). Never ship one you have only
  read the source of.
- **Red means failure, green means success.** No exceptions, no local overrides.
- **Verify every number** that appears in the diagram against the repo.
- **Ground every node in the repo** (§A6) — no invented components or flows.
- **Write the diagram, propose the commit** (§A3). Never run git.
- **Cap fix rounds at 2.** A blocking critique is a checkpoint to surface, not a
  to-do to silently work through.
