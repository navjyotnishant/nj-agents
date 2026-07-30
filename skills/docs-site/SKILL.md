---
name: docs-site
description: Use this skill when the user asks to "generate a documentation site", "build docs for this project", "make a browsable reference/guide", "document these skills/API/modules", or wants a polished HTML documentation page from existing docs, the codebase, an outline, or structured definition files. Auto-derives the menu/sections from the content, grounds everything in the source (flags gaps rather than inventing), embeds auto-redacted screenshots via the capture-screenshots pipeline when needed, produces a self-contained theme-aware docs.html, and PROPOSES the commit. Works in any git repo; nothing here is project-specific.
version: 0.1.0
class: authoring
---

# Docs Site (authoring, multi-agent)

Generates a **self-contained, browsable documentation site** (`docs.html`) from
whatever you point it at — existing docs/markdown, the codebase itself, a topic or
outline you give it, or structured definition files (SKILL.md, OpenAPI, JSON schema,
frontmatter). It derives the navigation from the content, keeps every statement
grounded in the source, embeds **auto-redacted** screenshots when a page needs them,
and **proposes** the commit — it never commits.

This is an **authoring-class** skill — follow `CONVENTIONS-authoring.md` (repo ingest
§A1, scoped output §A2, propose-commit §A3, placement §A4, MCP/tool-detect §A5,
grounding/safety §A6, non-clobber §A7).

> **Finding the conventions file.** It lives at the toolkit repo root, two levels
> above this skill — not beside `SKILL.md`. Skills are usually installed as
> symlinks into `~/.claude/skills/`, so a plain relative path resolves against the
> *link* and misses it. Resolve the link first:
>
> ```bash
> ROOT="$(dirname "$(readlink -f "<this skill's base directory>")")/.."
> ```
>
> then read `$ROOT/CONVENTIONS-authoring.md`. If a file is genuinely absent, say so and continue
> with the procedure below rather than stopping.

> **Spawning subagents — `CONVENTIONS-orchestration.md`.** This skill spawns agents,
> so `§C` (cost) and `§R` (progress reporting) apply. **Cost shape:** 1–2 agent calls.
> State it and get a yes before the first dispatch; cap fix rounds at 2; halt on any
> signal to stop. Announce the **pipeline** up front and each stage as it starts, so a stall is
attributable to a named stage (`§R`).

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  DOCS SITE — AUTHORING (multi-agent)                             ║
╠══════════════════════════════════════════════════════════════════╣
║  Builds a self-contained, browsable docs.html from your docs,    ║
║  code, outline, or definition files. Everything is grounded in    ║
║  the source — gaps are flagged, not invented. UI screenshots      ║
║  (if any) go through the capture-screenshots pipeline and are     ║
║  PII/secret-redacted before embedding. Writes docs.html and       ║
║  PROPOSES the commit — it never runs git.                        ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **Something to document** — existing docs, source code, a user-provided outline, or
  definition files. If there's nothing to read and no outline, ask what to document.
- **No external API / no network.** All analysis is the current Claude session.
- **Optional:** `pandoc` (if on PATH) for an extra Markdown export; the Figma/other
  MCPs are never required (§A5).

## Step 1 — Resolve inputs and scope

Determine what to document and from which sources (any combination):
- **Existing docs / markdown** — a `docs/` folder, README, `*.md` files.
- **The codebase** — modules, entry points, public API, config, CLI.
- **A topic / outline** the user provides (fill supporting detail from the repo).
- **Structured definition files** — `SKILL.md`/`agents/*.md`, OpenAPI/Swagger, JSON
  Schema, GraphQL SDL, front-matter-bearing files. Read their structure and render
  reference cards.

Confirm the **audience** and the **scope** (whole project vs. one area) if unclear.

## Step 2 — Ingest the sources

Per `CONVENTIONS-authoring.md §A1`, build the content model from the resolved inputs.
For definition files, parse their structure (names, fields, types, descriptions) so
the reference is accurate. Note what you read and what you skipped (large repos:
sample the most significant; say so).

## Step 3 — Architect the content

Spawn `docs-architect` with the content model. It:
- **auto-derives the menu/sections** and grouping from the content itself (not a fixed
  template) — the structure should reflect what's being documented;
- writes clear, grounded copy for each section/entry;
- **flags gaps** — where the source lacks information, it writes "not documented"
  rather than inventing (§A6). This is a *warning*, not a hard block: the site still
  generates, with gaps visible.

It returns a structured **doc model**: ordered sections → entries → content, plus a
list of any places a **screenshot** would help (with what to capture).

## Step 4 — Capture screenshots (delegated, auto-redacted)

If the doc model calls for UI/terminal screenshots, **invoke the `capture-screenshots`
skill** for each — do not roll your own capture. That pipeline captures, detects
PII/secrets, blurs/masks (full for high-risk, partial for illustrative), and
**verifies coverage before writing** — so every embedded image is already redacted and
the raw original never lands in the repo. Place the redacted images under the docs'
image dir and reference them from the doc model. If capture isn't possible (no running
app, no auth — never fabricate credentials), skip the image and note it as a gap.

## Step 5 — Design and build the page

Spawn `docs-designer` with the doc model (+ image paths). It produces a **single
self-contained `docs.html`**: a sidebar menu derived from the sections, tiered content
(scannable summary that expands to detail where it helps), theme-aware light/dark, no
external dependencies (all CSS/JS inline; images embedded or referenced by relative
path). It reuses the source's design system if one exists; otherwise it makes clean,
restrained, accessible choices.

## Step 6 — Placement + write

Per `CONVENTIONS-authoring.md §A4`: an existing docs location, else `docs.html` at the
repo root (or `docs/index.html` if a `docs/` tree exists). Report the chosen path.
Merge/refresh in place on re-run — keep the same path so links don't break (§A7).

## Step 7 — Summary + propose the commit

Summarize: what was documented, the sections generated, any **gaps flagged** (source
didn't cover them), which screenshots were captured/redacted or skipped, and where the
file landed. Then propose the commit per `CONVENTIONS-authoring.md §A3`:

```bash
git add docs.html <docs/images/...>
git commit -m "docs: generate documentation site"
git push
```

Never run git. Add a note on how to view it (open the file, or publish it as an
Artifact) and that gaps flagged in the page mean the *source* lacked that info.
