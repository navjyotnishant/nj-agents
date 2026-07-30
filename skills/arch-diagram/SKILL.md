---
name: arch-diagram
description: Use this skill when the user asks to "generate an architecture diagram", "draw the system architecture", "create a solution/deployment/data-flow/sequence/ER diagram", or wants a visual of how the project fits together. Reads the project's README, architecture docs, and ADRs first to ground the diagram, then generates it (default Excalidraw + an exported SVG; hand-authored SVG for simple diagrams, draw.io, mermaid, or Figma-via-MCP on request), places it into the project docs, and PROPOSES the commit. Works in any git repo; nothing here is project-specific.
version: 0.3.0
class: authoring
author: Navjyot Nishant
---

# Architecture Diagram (authoring)

Generates a **system / solution / sequence / data-flow / deployment / ER** diagram,
grounded in the project's own docs, and places it into the documentation. Default
output is an editable **Excalidraw** file (`.excalidraw`) **plus an exported SVG**
(so it renders on GitHub while staying editable at excalidraw.com). **draw.io is
available on request** for dense structural diagrams (mermaid, inline SVG, and
Figma-via-MCP also remain on request). It **writes the files** but only
**proposes** the commit.

This is an **authoring-class** skill — follow `CONVENTIONS-authoring.md` (repo
ingest §A1, scoped output §A2, propose-commit §A3, placement §A4, MCP-detect §A5,
grounding/safety §A6, non-clobber §A7). The **default path needs no hard tooling**:
Excalidraw exports via `npx excalidraw_export` when available, and the diagram agent
emits the SVG directly when it isn't (§A5). Only the **opt-in draw.io path** requires
a CLI, and it gates explicitly (Step 1.5) rather than silently swapping format — a
diagram is a visible, committed deliverable, so a silent downgrade would surprise the
user.

> **Finding the conventions file.** It lives at the toolkit repo root, two levels
> above this skill — not beside `SKILL.md`. Skills are usually installed as
> symlinks into `~/.claude/skills/`, so a plain relative path resolves against the
> *link* and misses it. Resolve the link first:
>
> ```bash
> ROOT="$(dirname "$(readlink -f "<this skill's base directory>")")/.."
> ```
>
> then read `$ROOT/CONVENTIONS-authoring.md` and `$ROOT/CONVENTIONS.md`. If a file is genuinely absent, say so and continue
> with the procedure below rather than stopping.

> **Spawning subagents — `CONVENTIONS-orchestration.md`.** This skill spawns agents,
> so `§C` (cost) and `§R` (progress reporting) apply. **Cost shape:** render → QA → fix loop, usually 2–4 agent calls.
> State it and get a yes before the first dispatch; cap fix rounds at 2; halt on any
> signal to stop. Announce each stage as it starts and report the **round against the cap** (`round 2/2`)
> so the loop visibly shows its bound (`§R`).

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  ARCHITECTURE DIAGRAM — AUTHORING                                ║
╠══════════════════════════════════════════════════════════════════╣
║  Reads your project + architecture docs, then generates a        ║
║  diagram (default: Excalidraw + exported SVG) and places it in    ║
║  your docs. It writes the diagram + doc edit, then PROPOSES the   ║
║  commit — it never runs git. Everything in the diagram is         ║
║  grounded in your repo; nothing is invented. No CLI needed for    ║
║  the default path; draw.io is available on request.               ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **Something to read** — README / `docs/` / `ARCHITECTURE.md` / ADRs, or source to
  skim. If the repo is essentially empty, say there's not enough to diagram and stop.
- **No hard tooling for the default path.** Excalidraw→SVG export uses `npx
  excalidraw_export` *if it runs*; if not, the diagram agent emits the SVG directly
  (§A5). Figma is used only if its MCP is connected.
- **The draw.io CLI, only for the opt-in draw.io path.** `drawio` on PATH
  (`brew install --cask drawio`; Linux/Windows: draw.io Desktop from
  github.com/jgraph/drawio-desktop). If a user asks for draw.io and it's missing, the
  **preflight gate** (Step 1.5) stops and offers to install it or fall back — it never
  auto-installs and never silently downgrades in interactive use.

  > **draw.io export footgun.** Its default SVG export embeds fonts *and* a base64
  > PNG of every text label — a ~15-node diagram came out at **1.2 MB, 96% pictures
  > of text**, which bloats the repo and makes diffs unreviewable. Always export with
  > `--embed-svg-fonts false` (drops it to ~56 KB with real `<text>` elements), then
  > strip draw.io's trailing "Text is not SVG - cannot display" notice. Export is also
  > **async** — poll for the output file rather than trusting the exit code.

## Step 1 — Resolve diagram type, mode, and format

- **Type** (from the user's prompt or a parameter): `system-arch` (default),
  `solution-arch`, `sequence`, `data-flow`, `deployment`, `er`. If unclear, ask.
- **Mode** — `structural` (default) or `conceptual`:
  - **structural** — the boxes are *real repo components* (services, modules, stores).
    Full grounding applies (§A6): every node/edge traces to the codebase.
  - **conceptual** — the boxes are *ideas*, not modules: a trust boundary, a request
    lifecycle, "where data is encrypted vs. in the clear," a mental model. Here the
    grounding rule relaxes: the **facts must still be true** (don't invent behavior),
    but a node need not map 1:1 to a file. Reach for hand-layout or the Excalidraw MCP
    rather than trying to derive the picture from module structure. Pick this mode when
    the user asks for a concept/flow/boundary rather than "how the code is wired."
  If the request is a concept and you diagram it structurally (or vice-versa), the
  result fights the intent — resolve the mode explicitly before drawing.
- **Format** (default **Excalidraw + SVG**). Preference order, cheapest first:
  1. `excalidraw` — **the default.** Editable `.excalidraw` + SVG, no CLI required,
     hand-drawn feel that suits architecture and concept diagrams.
  2. `svg` — self-contained `.svg`, authored directly. **Prefer this for simple
     diagrams** (see the cheap-path rule below) — zero tooling, zero export bugs.
  3. `mermaid` — fenced block, renders natively on GitHub, zero deps. Good when the
     diagram is a simple graph and living in the Markdown is an advantage.
  4. `drawio` — **on request.** Best for dense structural diagrams, but carries the
     export footgun above and needs a CLI.
  5. `figma` — only if the Figma MCP is detected (§A5).
  Confirm the choice if the user didn't specify. Only `drawio` triggers the preflight
  (Step 1.5).

### Cheap path first (cost control)

**A subagent is the expensive part of this skill, not the renderer.** A single
diagram can cost hundreds of thousands of tokens in `diagram-architect` +
`diagram-qa` turns while the export itself takes two seconds. Before spawning
anything:

- **Say the cost shape and get a yes.** *"This spawns an architect and a QA agent,
  usually 2–4 calls."* Don't discover the cost mid-run.
- **Skip `diagram-architect` for simple diagrams.** If the diagram is under ~15 nodes
  and you already understand the system from the repo ingest, author the SVG (or
  Excalidraw JSON) **directly**. The architect earns its cost on large or unfamiliar
  systems, not on a five-box flow.
- **Cap the QA loop at 2 rounds** (see Step 6a). Rounds three and beyond are where
  the spend goes, and the marginal gain is small.

## Step 1.5 — draw.io preflight gate (only when draw.io was requested)

Only runs when the user explicitly asked for **draw.io** (it is no longer the
default). Check for the CLI **before** generating anything:

```bash
command -v drawio
```

- **Present →** proceed on the draw.io path (Step 3 onward).
- **Missing, interactive →** **STOP. Do not silently switch formats.** Print the two
  choices and wait for the user:

  ```
  You asked for draw.io, but its CLI isn't installed. Choose one:

    (a) Install it, then re-run:
          macOS:    brew install --cask drawio        (links `drawio` on PATH)
          Linux/Win: draw.io Desktop — github.com/jgraph/drawio-desktop/releases
        Verify with:  drawio --version

    (b) Use the default Excalidraw route instead (no CLI needed) — say so and
        I'll generate an editable .excalidraw + SVG.
  ```

  Proceed only after the user installs (and confirms) **or** picks Excalidraw. Never
  auto-install.
- **Missing, non-interactive / CI** (`NJ_AGENTS_CI=1` / `--ci` per `CONVENTIONS.md §5`)
  **→** no one to prompt: **fall back to the default Excalidraw path**, note the
  fallback in the output, and continue. CI is never blocked on the diagram format.

## Step 2 — Ingest the architecture docs

Per `CONVENTIONS-authoring.md §A1`, architecture-focused: read `README*`,
`ARCHITECTURE.md`, everything under `docs/` (esp. `docs/architecture/`, `docs/adr/`,
`docs/decisions/`), design docs, and skim source **entry points** and top-level
module layout so the diagram reflects the real system. Note what you did and didn't
read.

## Step 3 — Detect output capabilities

Per §A5, detect what's available and pick the best render path:
- **Excalidraw MCP connected?** The best default path. It renders reliably (with
  draw-on animation) and returns an **editable excalidraw.com link** — a better
  authoring loop than a static export. Use its `read_me` once for the element format.
- **`npx excalidraw_export` available?** The default SVG exporter. It can fail in
  restricted environments (npm registry/tarball errors) — if it does, fall back to an
  agent-emitted SVG, don't block.
- **draw.io CLI (`drawio`) present?** Only relevant if draw.io was requested (already
  confirmed by the Step 1.5 gate). Export is **asynchronous** — the command returns
  (exit 0) a moment before the output file is flushed, so **poll** for the file to
  exist and be non-empty rather than trusting the exit code. Always pass
  `--embed-svg-fonts false` (see the footgun note in Prerequisites).
- **Figma MCP connected?** Only path for `figma` format.
- **A browser tool (Playwright) available?** Needed for the render-and-verify step
  (Step 6a) — it's how you actually *look* at the diagram before shipping it.

## Step 4 — Spawn the diagram-architect agent

Spawn `diagram-architect` with the repo model + chosen type + chosen format. It
returns:
- a **structured diagram model** (nodes = services/modules/stores, edges =
  calls/data-flow, boundaries), scoped to the type, and
- the **rendered artifact** in the chosen format — `.excalidraw` JSON by default
  (plus a matching `.svg` it emits directly when export tooling is unavailable), or
  valid `.drawio` XML when requested (the skill exports the SVG via the CLI), or
  mermaid / inline SVG / Figma-MCP calls.

Everything must trace to the repo (§A6) — no invented components.

## Step 5 — Resolve placement

Per `CONVENTIONS-authoring.md §A4`:
1. An existing `ARCHITECTURE.md` (add/update a section) or `docs/architecture/`.
2. Else a README "Architecture" section.
3. Else a new `docs/architecture/<type>.md`.

Default file paths for the **Excalidraw** format:
`docs/architecture/<type>.excalidraw` (editable source) + `docs/architecture/<type>.svg`
(rendered, embedded). For the opt-in draw.io path: `docs/architecture/<type>.drawio`
+ `docs/architecture/<type>.svg`. Report the chosen path and why.

## Step 6 — Write the artifact(s) and embed

- **draw.io (on request):** write the agent's `<type>.drawio` XML, then export the SVG
  via the CLI — **always with `--embed-svg-fonts false`**, or the file balloons to
  ~20x its size with base64 pictures of every text label:
  ```bash
  drawio --export --format svg --embed-svg-fonts false \
         --output docs/architecture/<type>.svg \
         docs/architecture/<type>.drawio --no-sandbox
  ```
  Afterwards, strip draw.io's trailing "Text is not SVG - cannot display" `<switch>`
  notice — it is misleading once real `<text>` elements are present.
  **Export is async** — after the command returns, poll for the output file (e.g. wait
  up to ~10s for `<type>.svg` to exist and be non-empty) before continuing; don't trust
  the exit code alone. For a raster, add on request: `--format png --scale 2` →
  `<type>.png`. If the export fails *despite* the CLI being present (rare), fall back to
  an agent-emitted SVG so the doc still renders — don't block. Embed the SVG:
  `![<type> architecture](./<type>.svg)` with a link to the `.drawio` ("edit at
  app.diagrams.net, or the VS Code Draw.io Integration extension").
- **Excalidraw (default):** write `<type>.excalidraw` and `<type>.svg` side by side. If
  `npx excalidraw_export <file>.excalidraw` succeeds, use its SVG; otherwise use the
  agent-emitted SVG. Embed the SVG in the target doc: `![System architecture](./<type>.svg)`
  with a link to the `.excalidraw` ("edit at excalidraw.com").
- **Mermaid:** embed the fenced ```mermaid block directly in the doc.
- **SVG:** write `<type>.svg` and embed via `![...](./<type>.svg)` (or inline).
- **Figma:** create via MCP; embed the Figma link + an exported PNG/SVG if available.

Update in place on re-run; keep the same filenames so doc links don't break (§A7).

## House "icon-tile" style (recommended for suite/overview & workflow diagrams)

For project-agnostic overview and workflow diagrams, this skill ships a
**self-contained renderer** in `scripts/` that produces the house style: **icon
tiles** (a crisp line icon on a soft chip, label under, class-color stripe) + soft
rounded cards + a **subtle Excalidraw hand-drawn texture** (rough.js) on borders and
connectors, wrapped in a **framed border**. It is deterministic, theme-neutral,
~20–40KB SVG, and needs no draw.io/Figma.

- **Setup (once):** `cd scripts && npm install` (installs rough.js locally;
  `node_modules` is gitignored). SVG→PNG for the QA visual pass uses `rsvg-convert`
  (ships with graphviz/cairo) — or any available SVG rasterizer.
- **Lane/tile diagrams** (suite overview, grouped maps): write a `*.iconmodel.json`
  (lanes → items with `icon`, `label`, `role`), then
  `node scripts/icon_diagram.js <model.json> <out.svg>`.
- **Flow diagrams** (pipelines, gates, fan-out): write a `*.flowmodel.json` (nodes on
  a `col`/`row` grid, `groups`, `edges`), then
  `node scripts/flow_diagram.js <model.json> <out.svg>`.
- **Semantic color is mandatory** (`diagram_common.js` documents it; `diagram-qa`
  enforces it): red=failure/block/stop, green=success/pass/output, class color for
  ordinary steps, grey for neutral inputs. Never green a failure or red a success.

draw.io / Excalidraw / mermaid / Figma remain available (above) for other diagram
types or when the user asks; the icon-tile renderer is the default for overviews and
flows.

## Step 6a — Render → QA → fix loop (MANDATORY, non-skippable gate)

**A diagram is not done when the file is written — it is done when it has passed QA.**
This is an enforced loop, not an eyeball: spawn the **`diagram-qa`** agent after every
render and do not proceed until it returns **PASS**.

1. **Render** the diagram to SVG (icon-tile renderer, or your chosen format).
2. **Spawn `diagram-qa`.** It runs the deterministic checker
   (`node scripts/qa_diagram.js <out.svg>`) — text overflow/clipping, node overlaps,
   dangling/overlapping **edge labels**, missing icons, empty-space/balance, and the
   **semantic-color** contract — plus a visual pass over a rasterized PNG (tofu
   glyphs, crowding, arrow legibility).
3. **On BLOCK, fix by issue kind, then re-render:**
   - **mechanical** (overflow, clipping, missing_icon, edge_label_clip) → the renderer
     already auto-fixes most (shrink-to-fit, canvas widen); if one remains, adjust the
     renderer/model minimally.
   - **layout / semantic_color** (overlap, empty_space, balance, edge_label_overlap,
     wrong outcome color) → `diagram-architect` adjusts the **model** (re-wrap rows,
     re-place a node, re-route an edge, pick the correct outcome color).
4. **Loop** render → `diagram-qa` until PASS, **capped at 2 fix rounds**. After two
   failed cycles on the same artifact, **stop and report**: what's fixed, what still
   fails, and the options. Do not start a third round without being asked — that is
   where the token spend goes and the marginal gain is smallest. A BLOCK verdict is a
   checkpoint to surface, not a to-do to silently work through.

Clean up any scratch PNGs/wrappers — they never belong in the repo (the committed
outputs are the `.svg`, its editable source, and optionally a `.png`).

## Step 7 — Summary + propose commit

Give a detailed summary: what the diagram shows (the key components and flows), which
type/format, where it landed, and **how to view/edit** it (SVG renders on GitHub; open
the `.excalidraw` at excalidraw.com; the opt-in `.drawio` at app.diagrams.net or the
VS Code Draw.io extension; mermaid renders in GitHub Markdown). If a draw.io run fell
back to Excalidraw because the CLI was absent, **say so** here. If you skipped
`diagram-architect` because the diagram was simple enough to author directly, say that
too — it tells the user why it was fast.

Then propose the commit per `CONVENTIONS-authoring.md §A3` (default Excalidraw paths
shown; swap `.excalidraw` → `.drawio` if draw.io was requested):
```bash
git add docs/architecture/<type>.excalidraw docs/architecture/<type>.svg <edited-doc>
git commit -m "docs: add <type> architecture diagram"
git push
```
Never run git. Add a validation note: open the SVG on GitHub / the `.excalidraw` at
excalidraw.com to confirm it reads correctly before pushing.
