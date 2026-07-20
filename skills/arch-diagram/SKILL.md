---
name: arch-diagram
description: Use this skill when the user asks to "generate an architecture diagram", "draw the system architecture", "create a solution/deployment/data-flow/sequence/ER diagram", or wants a visual of how the project fits together. Reads the project's README, architecture docs, and ADRs first to ground the diagram, then generates it (default draw.io + an exported SVG; Excalidraw fallback, mermaid, inline SVG, or Figma-via-MCP on request), places it into the project docs, and PROPOSES the commit. Works in any git repo; nothing here is project-specific.
version: 0.2.0
---

# Architecture Diagram (authoring)

Generates a **system / solution / sequence / data-flow / deployment / ER** diagram,
grounded in the project's own docs, and places it into the documentation. Default
output is an editable **draw.io** file (`.drawio`) **plus an exported SVG** (so it
renders on GitHub while staying editable in draw.io / diagrams.net). **Excalidraw is
the fallback** (mermaid, inline SVG, and Figma-via-MCP remain on request). It
**writes the files** but only **proposes** the commit.

This is an **authoring-class** skill — follow `CONVENTIONS-authoring.md` (repo
ingest §A1, scoped output §A2, propose-commit §A3, placement §A4, MCP-detect §A5,
grounding/safety §A6, non-clobber §A7). **One deliberate §A5 deviation:** the draw.io
default path *requires* the draw.io CLI and uses a **hard preflight gate** (Step 1.5)
instead of silently degrading — a diagram is a visible, committed deliverable, so a
silent format swap would surprise the user. The gate still offers a first-class
Excalidraw escape and never auto-installs, honoring the spirit of §A5 (the user
controls tooling) while being explicit about the format.

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  ARCHITECTURE DIAGRAM — AUTHORING                                ║
╠══════════════════════════════════════════════════════════════════╣
║  Reads your project + architecture docs, then generates a        ║
║  diagram (default: draw.io + exported SVG) and places it in your  ║
║  docs. It writes the diagram + doc edit, then PROPOSES the        ║
║  commit — it never runs git. Everything in the diagram is         ║
║  grounded in your repo; nothing is invented. draw.io CLI is       ║
║  required for the default path (or choose the Excalidraw route).  ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **Something to read** — README / `docs/` / `ARCHITECTURE.md` / ADRs, or source to
  skim. If the repo is essentially empty, say there's not enough to diagram and stop.
- **The draw.io CLI, for the default path.** The default format exports via the
  draw.io desktop CLI (`drawio` on PATH — `brew install --cask drawio` links it to
  `/opt/homebrew/bin/drawio`; Linux/Windows: install draw.io Desktop from
  github.com/jgraph/drawio-desktop). If it's missing, the **preflight gate** (Step 1.5)
  stops and offers to either install it or switch to the Excalidraw route — it never
  auto-installs and never silently downgrades in interactive use.
- **Fallback path needs no hard tooling.** Excalidraw→SVG export uses `npx
  excalidraw_export` *if it runs*; if not, the diagram agent emits the SVG directly
  (§A5). Figma is used only if its MCP is connected.

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
- **Format** (default **draw.io + SVG**). Alternatives, on request:
  - `excalidraw` — editable `.excalidraw` + SVG (the fallback; hand-drawn feel).
  - `mermaid` — fenced block, renders natively on GitHub, zero deps.
  - `svg` — self-contained inline/`.svg`, no tooling.
  - `figma` — only if the Figma MCP is detected (§A5).
  Confirm the choice if the user didn't specify. If the user explicitly asks for a
  non-default format, skip the draw.io preflight (Step 1.5) — it only gates the default.

## Step 1.5 — draw.io preflight gate (default path only)

If the resolved format is the default (**draw.io**), check for the CLI **before**
generating anything:

```bash
command -v drawio
```

- **Present →** proceed on the draw.io path (Step 3 onward).
- **Missing, interactive →** **STOP. Do not silently switch formats.** Print the two
  choices and wait for the user:

  ```
  The draw.io CLI isn't installed — it's required for the default diagram format.
  Choose one:

    (a) Install it, then re-run:
          macOS:    brew install --cask drawio        (links `drawio` on PATH)
          Linux/Win: draw.io Desktop — github.com/jgraph/drawio-desktop/releases
        Verify with:  drawio --version

    (b) Use the Excalidraw route instead (no draw.io needed) — say so and I'll
        generate an editable .excalidraw + SVG.
  ```

  Proceed only after the user installs (and confirms) **or** picks Excalidraw. Never
  auto-install.
- **Missing, non-interactive / CI** (`NJ_AGENTS_CI=1` / `--ci` per `CONVENTIONS.md §5`)
  **→** no one to prompt: **fall back to Excalidraw**, note the fallback in the output,
  and continue. CI is never blocked on the diagram format.

## Step 2 — Ingest the architecture docs

Per `CONVENTIONS-authoring.md §A1`, architecture-focused: read `README*`,
`ARCHITECTURE.md`, everything under `docs/` (esp. `docs/architecture/`, `docs/adr/`,
`docs/decisions/`), design docs, and skim source **entry points** and top-level
module layout so the diagram reflects the real system. Note what you did and didn't
read.

## Step 3 — Detect output capabilities

Per §A5, detect what's available and pick the best render path:
- **draw.io CLI (`drawio`) present?** The default export path (already confirmed by the
  Step 1.5 gate). Export is **asynchronous** — the command returns (exit 0) a moment
  before the output file is flushed, so after running it you must **poll** for the file
  to exist and be non-empty rather than trusting the exit code alone.
- **Excalidraw MCP connected?** Prefer it for Excalidraw output. It renders reliably
  (with draw-on animation) and returns an **editable excalidraw.com link** — a better
  authoring loop than a static export. Use its `read_me` once for the element format.
- **`npx excalidraw_export` available?** The fallback SVG exporter. Note it can fail in
  restricted environments (npm registry/tarball errors) — if it does, fall back to an
  agent-emitted SVG, don't block.
- **Figma MCP connected?** Only path for `figma` format.
- **A browser tool (Playwright) available?** Needed for the render-and-verify step
  (Step 6a) — it's how you actually *look* at the diagram before shipping it.

## Step 4 — Spawn the diagram-architect agent

Spawn `diagram-architect` with the repo model + chosen type + chosen format. It
returns:
- a **structured diagram model** (nodes = services/modules/stores, edges =
  calls/data-flow, boundaries), scoped to the type, and
- the **rendered artifact** in the chosen format — valid `.drawio` XML by default
  (the skill exports the SVG via the CLI), or `.excalidraw` JSON (fallback; plus a
  matching `.svg` it emits directly if export tooling is unavailable), or mermaid /
  inline SVG / Figma-MCP calls.

Everything must trace to the repo (§A6) — no invented components.

## Step 5 — Resolve placement

Per `CONVENTIONS-authoring.md §A4`:
1. An existing `ARCHITECTURE.md` (add/update a section) or `docs/architecture/`.
2. Else a README "Architecture" section.
3. Else a new `docs/architecture/<type>.md`.

Default file paths for the **draw.io** format:
`docs/architecture/<type>.drawio` (editable source) + `docs/architecture/<type>.svg`
(rendered, embedded). For the Excalidraw fallback: `docs/architecture/<type>.excalidraw`
+ `docs/architecture/<type>.svg`. Report the chosen path and why.

## Step 6 — Write the artifact(s) and embed

- **draw.io (default):** write the agent's `<type>.drawio` XML, then export the SVG via
  the CLI:
  ```bash
  drawio --export --format svg --output docs/architecture/<type>.svg \
         docs/architecture/<type>.drawio --no-sandbox
  ```
  **Export is async** — after the command returns, poll for the output file (e.g. wait
  up to ~10s for `<type>.svg` to exist and be non-empty) before continuing; don't trust
  the exit code alone. For a raster, add on request: `--format png --scale 2` →
  `<type>.png`. If the export fails *despite* the CLI being present (rare), fall back to
  an agent-emitted SVG so the doc still renders — don't block. Embed the SVG:
  `![<type> architecture](./<type>.svg)` with a link to the `.drawio` ("edit at
  app.diagrams.net, or the VS Code Draw.io Integration extension").
- **Excalidraw (fallback):** write `<type>.excalidraw` and `<type>.svg` side by side. If
  `npx excalidraw_export <file>.excalidraw` succeeds, use its SVG; otherwise use the
  agent-emitted SVG. Embed the SVG in the target doc: `![System architecture](./<type>.svg)`
  with a link to the `.excalidraw` ("edit at excalidraw.com").
- **Mermaid:** embed the fenced ```mermaid block directly in the doc.
- **SVG:** write `<type>.svg` and embed via `![...](./<type>.svg)` (or inline).
- **Figma:** create via MCP; embed the Figma link + an exported PNG/SVG if available.

Update in place on re-run; keep the same filenames so doc links don't break (§A7).

## Step 6a — Render and VERIFY before you ship it (do not skip)

**A diagram is not done when the file is written — it is done when it has been looked
at and is clean.** Overlaps are invisible in the source and only appear on screen;
this is the step that catches the crowded, unreadable output that hand-authored or
agent-emitted diagrams otherwise ship.

1. **Render to an image.** Load the SVG (or an HTML wrapper around it) in the browser
   tool and screenshot it; for mermaid, render the fenced block; for the Excalidraw
   MCP, use its rendered view. If no renderer is available at all, say so plainly in
   the summary — an unverified diagram is a known risk, not a silent pass.
2. **Inspect the screenshot for these specific failures** (the ones that actually
   happen):
   - text overlapping other text, or a label overlapping a box border;
   - connector lines routed **through** a node instead of around it;
   - annotation/callout text colliding with the body text of its own box;
   - labels or nodes clipped outside the canvas / viewBox;
   - any emoji or glyph rendering as tofu (□) — emoji in SVG/Excalidraw text is
     unreliable; if it doesn't paint, replace it with a drawn shape or plain text.
3. **A cheap pre-check:** before rendering, compare element bounding boxes — if two
   text/node boxes intersect, you already have an overlap to fix. This catches most
   problems without a render.
4. **Fix and re-render** until it reads cleanly. Only then continue to Step 7. Loop
   here rather than shipping "probably fine."

Clean up any preview scratch files (HTML wrappers, temporary PNGs) — they never belong
in the repo.

## Step 7 — Summary + propose commit

Give a detailed summary: what the diagram shows (the key components and flows), which
type/format, where it landed, and **how to view/edit** it (SVG renders on GitHub; open
the `.drawio` at app.diagrams.net or the VS Code Draw.io extension; the `.excalidraw`
fallback at excalidraw.com; mermaid renders in GitHub Markdown). If a non-interactive
run fell back to Excalidraw because the draw.io CLI was absent, **say so** here.

Then propose the commit per `CONVENTIONS-authoring.md §A3` (default draw.io paths shown;
swap `.drawio` → `.excalidraw` on the fallback path):
```bash
git add docs/architecture/<type>.drawio docs/architecture/<type>.svg <edited-doc>
git commit -m "docs: add <type> architecture diagram"
git push
```
Never run git. Add a validation note: open the SVG on GitHub / the `.drawio` in draw.io
to confirm it reads correctly before pushing.
