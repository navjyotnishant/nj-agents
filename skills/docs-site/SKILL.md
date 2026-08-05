---
name: docs-site
description: Use this skill when the user asks to "generate a documentation site", "build docs for this project", "make a browsable reference/guide", "document these skills/API/modules", or wants browsable documentation from existing docs, the codebase, an outline, or structured definition files. By DEFAULT it builds a generated multi-page site (MkDocs Material + gen-files + literate-nav) with a tree/sidebar nav, one page per entity, and embedded diagrams — rebuilt from the source files on every commit so it cannot drift. Pass --single for one self-contained theme-aware HTML page instead (a snapshot, for hand-maintained prose). Auto-derives the menu/sections, grounds everything in the source (flags gaps rather than inventing), embeds auto-redacted screenshots via the capture-screenshots pipeline when needed, and PROPOSES the commit. Works in any git repo; nothing here is project-specific.
version: 0.2.0
class: authoring
author: navjyotnishant
---

# Docs Site (authoring, multi-agent)

Generates **browsable documentation** from whatever you point it at — existing
docs/markdown, the codebase itself, a topic or outline you give it, or structured
definition files (SKILL.md, OpenAPI, JSON schema, frontmatter). It derives the
navigation from the content, keeps every statement grounded in the source, embeds
**auto-redacted** screenshots when a page needs them, and **proposes** the commit — it
never commits.

**By default it builds a generated multi-page site** — tree/sidebar nav, one page per
entity, diagrams embedded, rebuilt from the source on every commit so it cannot drift.
Pass **`--single`** for one self-contained HTML page instead, which is a snapshot and
will drift (see Step 5).

This is an **authoring-class** skill — follow `CONVENTIONS-authoring.md` (repo ingest
§A1, scoped output §A2, propose-commit §A3, placement §A4, MCP/tool-detect §A5,
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
> then read `$ROOT/CONVENTIONS-authoring.md`. If a file is genuinely absent, say so and continue
> with the procedure below rather than stopping.

> **Every skill follows `CONVENTIONS-orchestration.md` §U** — ground everything in
> the actual repo, never run git on your own initiative, no secrets in output,
> keep `CHANGELOG.md` current when the change is user-facing, degrade rather than
> fail, and say what you did not do.

> **Spawning subagents — `CONVENTIONS-orchestration.md`.** This skill spawns agents,
> so `§C` (cost) and `§R` (progress reporting) apply. **Cost shape:** 1–2 agent calls.
> State it and get a yes before the first dispatch; cap fix rounds at 2; halt on any
> signal to stop. Announce the **pipeline** up front and each stage as it starts, so a stall is
> attributable to a named stage (`§R`).


## Dependencies

Detected at runtime, never installed by this skill (`§A5`).

| Tool | Used for | Without it |
|---|---|---|
| `mkdocs` + `mkdocs-material` + `mkdocs-gen-files` + `mkdocs-literate-nav` | the default generated site (Mode A) | say so and offer `--single` (Mode B), which needs no toolchain |
| `mkdocs-glightbox` | click-to-expand for wide diagrams | diagrams render inline, shrunk to the column |

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  DOCS SITE — AUTHORING (multi-agent)                             ║
╠══════════════════════════════════════════════════════════════════╣
║  Builds a GENERATED multi-page site (tree nav, one page per      ║
║  entity, diagrams embedded) that rebuilds from the source and     ║
║  cannot drift. --single gives one self-contained page instead.    ║
║  Everything is grounded in the source — gaps are flagged, not     ║
║  invented. UI screenshots (if any) go through the                 ║
║  capture-screenshots pipeline and are PII/secret-redacted         ║
║  before embedding. PROPOSES the commit — it never runs git.       ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **Something to document** — existing docs, source code, a user-provided outline, or
  definition files. If there's nothing to read and no outline, ask what to document.
- **No external API / no network.** All analysis is the current AI session.
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

## Step 5 — Design and build

Two modes. **Mode A — the generated site — is the default.** Reach for B only when the
subject is *prose that a human maintains* (a guide, a handbook), or when the deliverable
must be one file you can email or open with no toolchain.

**Why generated is the default:** documentation that is written once starts drifting the
moment the code moves, and nobody notices until a reader follows a wrong instruction. A
single-file page has to be *regenerated and re-committed* by someone who remembers to;
a generated site rebuilds from the source on every commit and **cannot** be wrong about
what exists. If the subject is code, definition files, or an API — anything with a
structure to derive — the answer is Mode A. This repo's own reference is Mode A, and it
replaced a hand-updated page that had silently drifted to documenting 21 of 37 skills.

### Mode A — a generated multi-page site (default)

Build a site that is regenerated from the source files on every commit rather than
written once. MkDocs Material with `mkdocs-gen-files` and `mkdocs-literate-nav` is the
path with the least ceremony.

**The rule that makes it worth doing:** pages are written into the *virtual* docs tree
at build time. Nothing generated lands on disk, so a page **cannot** disagree with the
file it documents. If a page can go stale, the build is wrong.

What this produces, and what to hold it to:

- **A tree/sidebar nav derived from the content** — emit a `SUMMARY.md` and let
  `literate-nav` build the tree. A flat menu is the thing you are moving away from.
- **One page per entity** (skill/agent/module/endpoint), plus group overviews and, where
  a pipeline exists, an orchestrator page showing dispatch order.
- **Diagrams embedded from their source dir** — copy them into the virtual tree at build
  time rather than duplicating them on disk.
- **Fail loudly on an entity type the generator has no page for.** A type present in the
  source but missing from the generator's class map produces *no page*, silently — and
  stays invisible until something links to it and `--strict` fails on the dangling link.
  That exact bug shipped in this repo (the `testing` class was absent from `CLASSES`).

**The rule that makes it worth doing:** pages are written into the *virtual* docs tree
at build time. Nothing generated lands on disk, so a page **cannot** disagree with the
file it documents. If a page can go stale, the build is wrong.

Hard-won specifics, each of which cost a broken build or a broken page:

- **`docs_dir` must not be a directory that already holds artifacts.** Pointing MkDocs
  at an existing `docs/` sweeps diagrams, JSON and stray files into the nav. Use a
  separate source dir.
- **The generator script lives inside `docs_dir`,** so MkDocs treats it as a static
  file and *publishes it*. Exclude it explicitly (`exclude_docs`).
- **Never list the same page twice in the nav.** MkDocs keeps the first occurrence and
  silently **drops** the rest — a whole section can vanish while the build stays green.
  If two places need to reference one page, make one of them a link, not a nav entry.
- **The nav label becomes the page title.** A generic label like "Workflow" repeated
  across entries produces a set of identically-titled pages.
- **Generate in dependency order.** A page linking to one that has not been written
  yet fails under `--strict`, which is exactly what you want it to do.
- **Derive cross-references, never retype them.** Recover them from the source and
  **fail the build** on one that does not resolve. A dead link that ships is worse
  than a build that stops.
- **Diagrams are wider than the content column.** Add a lightbox (`mkdocs-glightbox`)
  so they can be opened full-size, and give them a white background in dark mode if
  they are drawn on white.
- **Verify in a browser, not by grepping the built HTML.** Material loads the nav via
  JS, so `curl` sees a shell — a nav can be visibly broken while every grep passes.
- **Never tell anyone to open the built `index.html` from disk.** With directory URLs
  on (the default), every internal link points at a *directory* (`href="skills/foo/"`).
  A browser cannot resolve that over `file://`, so it lands on the directory instead of
  its `index.html` and the page renders as **unstyled HTML that looks like a broken
  build**. It isn't — it is the wrong way to open a correct site. Always hand over a
  **served URL** (`mkdocs serve`, or the deployed one).
- **Hand over the URL including its base path.** When `site_url` carries a subpath (a
  GitHub Pages project site is `https://user.github.io/<repo>/`), the dev server serves
  under that prefix and `302`s `/` → `/<repo>/`. Give the full path — a bare
  `127.0.0.1:8000` link plus a `404` on the first page they click reads as a broken site.

Pin the toolchain in `requirements-docs.txt` and deploy from CI. **GitHub Pages needs
a public repo on a free plan** — check before promising a URL.

### Mode B — one self-contained page (`--single`)

For hand-maintained prose, or when the deliverable must be a single file that opens with
no toolchain. Spawn `docs-designer` with the doc model (+ image paths). It produces a
**single self-contained page**: a sidebar menu derived from the sections, tiered content
(scannable summary that expands to detail where it helps), theme-aware light/dark, no
external dependencies (all CSS/JS inline; images embedded or referenced by relative
path). It reuses the source's design system if one exists; otherwise it makes clean,
restrained, accessible choices.

**Say the tradeoff out loud when you pick this mode:** the page is a snapshot. It is
correct the day it is written and drifts from then on, and nothing will announce that it
has. If the subject has a derivable structure, offer Mode A instead — and if the user
still wants one file, note in the page itself when it was generated and from what.

**Never run both modes into the same repo.** Two references that disagree is worse than
one that is merely dated: a reader has no way to tell which is current. If a generated
site already exists, updating *it* is the answer.

## Step 6 — Placement + write

Per `CONVENTIONS-authoring.md §A4`, and it differs by mode:

- **Mode A (generated site)** — commit the *inputs*, never the output: the config
  (`mkdocs.yml`), the generator (in its own source dir, not a dir already holding
  artifacts), the pinned `requirements-docs.txt`, and the CI workflow. **Gitignore the
  built site** (`site/`); a committed build is the drift you are trying to prevent.
- **Mode B (`--single`)** — an existing docs location, else a single HTML file at the
  repo root (or `docs/index.html` if a `docs/` tree exists). Report the chosen path.

Merge/refresh in place on re-run — keep the same path so links don't break (§A7).

**Before proposing anything in Mode A, build it:** `mkdocs build --strict` must pass.
A dangling cross-reference is exactly what `--strict` exists to catch, and shipping a
config whose build fails is worse than shipping no config.

## Step 7 — Summary + propose the commit

Summarize: what was documented, the sections/pages generated, any **gaps flagged**
(source didn't cover them), which screenshots were captured/redacted or skipped, and
where things landed. Then propose the commit per `CONVENTIONS-authoring.md §A3` — the
file list depends on the mode:

```bash
# Mode A — the generated site: commit the inputs, not the build
git add mkdocs.yml <gen-script> requirements-docs.txt .github/workflows/<docs>.yml
git commit -m "docs: generate the reference site from source"

# Mode B — the single page
git add <the-page>.html <docs/images/...>
git commit -m "docs: generate documentation page"
```

Never run git. Note that gaps flagged in the output mean the *source* lacked that info.

**Then say how to view it — and get this right, because a correct site opened the wrong
way looks broken.**

- **Mode A** — give a **served URL**, never a path to the built `index.html`. Start the
  server, confirm the page actually returns `200`, and hand over the full URL *including
  any base path* from `site_url`:

  ```bash
  <venv>/bin/mkdocs serve      # then open http://127.0.0.1:8000/<base-path>/
  ```

  Plus the published URL if CI deploys it. Opening the file from disk gives unstyled
  HTML and dead links (directory URLs don't resolve over `file://`) — every time, and it
  will be reported to you as a broken build.
- **Mode B** — open the file; a single self-contained page has no such problem.
