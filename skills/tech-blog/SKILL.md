---
name: tech-blog
description: Use this skill when the user asks to "write a technical blog about this project", "draft a blog post explaining the architecture", "write an engineering article about what we built", or wants an expert-level technical write-up of the project. Runs a multi-agent pipeline (writer → fact-checker → reviewer → editor → optional poster), grounds every claim in the actual repo (the fact-checker BLOCKS on anything it can't verify), embeds architecture diagrams if present, writes the post to docs/blog/, and produces publish-ready Markdown + HTML. Posts via an MCP only if one is connected and you opt in. Works in any git repo; nothing here is project-specific.
version: 0.1.0
---

# Technical Blog (authoring, multi-agent)

Produces an expert-level technical blog post explaining the project, via a
**sequential multi-agent pipeline**: `blog-writer` → `blog-fact-checker` →
`blog-reviewer` → `blog-editor` → optional `blog-poster`. Every claim is grounded in
the real repo — the fact-checker **blocks** finalization on anything it can't verify.
It writes the final post to the repo and **proposes** the commit; it posts to an
external platform only if an MCP is connected and you opt in.

This is an **authoring-class** skill — follow `CONVENTIONS-authoring.md` (repo
ingest §A1, scoped output §A2, propose-commit §A3, placement §A4, MCP-detect §A5,
grounding/safety §A6, non-clobber §A7).

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  TECHNICAL BLOG — AUTHORING (multi-agent)                        ║
╠══════════════════════════════════════════════════════════════════╣
║  Pipeline: writer → fact-checker → reviewer → editor → (poster).  ║
║  Every claim is grounded in your actual repo; the fact-checker    ║
║  BLOCKS the post from finalizing on any claim it can't verify.    ║
║  Writes the post to docs/blog/ + a publish-ready MD/HTML copy,    ║
║  then PROPOSES the commit. Posts externally only if an MCP is     ║
║  connected and you opt in — never auto-publishes.                ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`) with code and/or docs to write
  about; else stop.
- **No required tooling.** `pandoc` (if on PATH) renders the HTML copy; absent, the
  Markdown copy is still produced. A publishing MCP is used only if connected (§A5).

## Step 1 — Deep repo-context ingest

Per `CONVENTIONS-authoring.md §A1`, **deep**: README, `docs/`, architecture docs,
key source (entry points, core modules, public API). Also **discover any Bundle-2
diagrams** (`docs/architecture/*.svg` / `*.excalidraw` / mermaid blocks) to embed or
reference in the post. Build the repo model the whole pipeline will be grounded in.

## Step 2 — Confirm topic, angle, audience, landing path

Ask (or accept as parameters): the **topic/angle** (e.g. "how we built X", "our
architecture", "lessons from Y"), the **audience** (e.g. senior engineers, general
dev), and confirm the **landing path** (default `docs/blog/<slug>.md`, §A4). Derive a
URL-safe `<slug>` from the title.

## Step 3 — Writer

Spawn `blog-writer` with the repo model + topic/angle/audience. It produces a draft
to the **scratchpad** (not the repo). The draft cites where each technical claim
comes from (file/module) so the fact-checker can verify.

## Step 4 — Fact-checker (BLOCKING gate)

Spawn `blog-fact-checker` on the draft. It verifies **every technical claim** against
the actual repo — APIs, features, file paths, behavior, versions. It returns each
claim marked **verified / unverifiable / wrong**.

- **Any `wrong` or `unverifiable` claim → the post cannot finalize.** Send the
  annotations back to `blog-writer` to fix (correct it) or cut it, then re-check.
  Loop until the fact-checker reports **no wrong/unverifiable claims remain**. Do not
  proceed to publish with an unresolved claim (this is a hard gate, §A6).

## Step 5 — Reviewer

Spawn `blog-reviewer` on the fact-clean draft. It critiques structure, clarity,
technical depth, narrative flow, and audience fit — returning actionable notes (not a
rewrite).

## Step 6 — Editor

Spawn `blog-editor` with the draft + fact-checker cuts + reviewer notes. It produces
the **final** polished post: applies the notes, ensures every fact-checker correction
landed, embeds the architecture diagrams (Step 1) at the right points, and adds
front-matter (title, date, tags, summary).

## Step 7 — Write outputs

- Write the final post to `docs/blog/<slug>.md` (§A4; merge/revise if the slug exists,
  §A7).
- Write **publish-ready copies to the scratchpad**: the Markdown, and — if `pandoc`
  is on PATH — a standalone HTML render (`pandoc <slug>.md -s -o <slug>.html`). If
  `pandoc` is absent, note that only Markdown was produced.

## Step 8 — Optional poster

Detect a publishing MCP (§A5) — a CMS / Dev.to / Medium / Notion connector, etc. If
one is connected **and the user opts in**, spawn `blog-poster` to create a **draft**
on that platform (never auto-publish without explicit confirmation).

If no MCP is connected but the target is **Dev.to** and the user opts in, `blog-poster`
has a direct-REST fallback: `scripts/publish-devto.py <post.md>` creates a draft via
the Dev.to API (uploads local images to Dev.to's CDN, forces `published: false`,
idempotent re-runs). It needs a `DEVTO_API_KEY` — exported or in `~/.claude/.env`
(Dev.to → Settings → Extensions → "DEV Community API Keys"). If neither path applies,
stop here and hand the user the publish-ready MD/HTML files with manual posting
instructions.

## Step 9 — Propose the commit

Per `CONVENTIONS-authoring.md §A3`, for the repo copy:
```bash
git add docs/blog/<slug>.md
git commit -m "docs: add technical blog — <title>"
git push
```
Never run git. Summarize: the post's angle, where it landed, the publish-ready files,
how many fact-check iterations it took, and any claim that was cut for being
unverifiable.
