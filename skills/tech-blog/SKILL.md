---
name: tech-blog
description: Use this skill when the user asks to "write a technical blog about this project", "draft a blog post explaining the architecture", "write an engineering article about what we built", or wants an expert-level technical write-up of the project. Runs a multi-agent pipeline (writer → fact-checker → reviewer → editor → optional poster), grounds every claim in the actual repo (the fact-checker BLOCKS on anything it can't verify), embeds architecture diagrams if present, writes the post to docs/blog/, and produces publish-ready Markdown + HTML. Posts via an MCP only if one is connected and you opt in. Works in any git repo; nothing here is project-specific.
version: 0.1.0
class: authoring
author: navjyotnishant
---

# Technical Blog (authoring, multi-agent)

Produces an expert-level technical blog post explaining the project via a
**multi-agent pipeline**. The content chain is **sequential** —
`blog-writer` → `blog-fact-checker` → `blog-reviewer` → `blog-editor` (each transforms
the prior; the fact-checker **blocks** finalization on anything it can't verify).
Alongside the writer it **generates the visual assets** the post needs — architecture
diagrams via the `arch-diagram` skill and redacted product screenshots via
`capture-screenshots` — so the editor has real figures to embed. After the editor, the
independent finalize checks — `blog-final-polish`, `blog-platform-lint`, and cover
generation — **run in parallel** (they only need the finished post), then converge
before the optional `blog-poster` and, once published, optional `social-post` promo
copy. Every claim is grounded in the real repo. It writes the final post to the repo and
**proposes** the commit; it posts to an external platform only if an MCP is connected
(or the Dev.to REST fallback is configured) and you opt in.

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
> then read `$ROOT/CONVENTIONS-authoring.md`. If a file is genuinely absent, say so and continue
> with the procedure below rather than stopping.

> **Every skill follows `CONVENTIONS-orchestration.md` §U** — ground everything in
> the actual repo, never run git on your own initiative, no secrets in output,
> keep `CHANGELOG.md` current when the change is user-facing, degrade rather than
> fail, and say what you did not do.

> **Spawning subagents — `CONVENTIONS-orchestration.md`.** This skill spawns agents,
> so `§C` (cost) and `§R` (progress reporting) apply. **Cost shape:** a 6-agent pipeline (writer → fact-checker → reviewer → editor → final-polish → platform-lint).
> State it and get a yes before the first dispatch; cap fix rounds at 2; halt on any
> signal to stop. Announce the **pipeline** up front and each stage as it starts, so a stall is
> attributable to a named stage (`§R`).


## Dependencies

Detected at runtime, never installed by this skill (`§A5`).

| Tool | Used for | Without it |
|---|---|---|
| `rsvg-convert` | rasterising generated diagrams | embeds the SVG directly |
| `DEVTO_API_KEY` or a publishing MCP | posting a draft, on opt-in | hands you the publish-ready files |

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  TECHNICAL BLOG — AUTHORING (multi-agent)                        ║
╠══════════════════════════════════════════════════════════════════╣
║  Sequential: writer → fact-checker → reviewer → editor.          ║
║  Alongside the writer: arch-diagram + capture-screenshots.       ║
║  Then in PARALLEL: final-polish + platform-lint + cover-gen.      ║
║  Converge → (poster) → (social-post promo).                      ║
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
key source (entry points, core modules, public API). Also **discover any existing
architecture diagrams** (`docs/architecture/*.svg` / `*.drawio` / `*.excalidraw` /
mermaid blocks) to embed or reference in the post. Build the repo model the whole
pipeline will be grounded in.

## Step 2 — Confirm topic, angle, audience, voice, landing path

Ask (or accept as parameters): the **topic/angle** (e.g. "how we built X", "our
architecture", "lessons from Y"), the **audience** (e.g. senior engineers, general
dev), the **voice**, any **style prefs** (`style_prefs` — e.g. "no em-dashes", house
spelling, sentence-case headings; passed through to the editor and final-polish), and
confirm the **landing path** (default `docs/blog/<slug>.md`, §A4). Derive a URL-safe
`<slug>` from the title.

**Voice** — default to a real practitioner writing, not a neutral explainer: first
person where natural, contractions, varied sentence length, an actual point of view,
the occasional aside. **Actively avoid the AI-symmetry tells**: relentless tricolons,
over-balanced "not X but Y" constructions, and every paragraph the same shape. The
first drafts of this pipeline drift toward that register unless steered — steer it up
front, and have the reviewer (Step 5) flag AI-symmetry as a finding if it creeps in.

### Revising an existing post (don't regenerate from scratch)

If the user asks to **change an existing post** — reframe the angle, adjust
positioning, cut or add a section, retitle — do NOT re-run the whole writer pipeline
from zero. Revise in place:
1. Start from the current post, apply the requested change (writer or editor, as fits
   the size of the change).
2. Re-run `blog-fact-checker` (Step 4) — but scoped to **new or changed claims**; a
   reframe can carry old prose forward, and the checker must re-verify anything the
   change touched (it has caught claims silently carried over from a prior draft).
3. Editor (Step 6) finalizes; re-emit outputs (Step 7) and **re-publish the same
   artifact/HTML** so the review link stays current.
Keep the same `<slug>`/filename so links don't break (§A7).

## Step 2.5 — Prepare visual assets (generate, don't only embed)

Now that the topic/angle is known, decide what **figures** the post needs — an
architecture/data-flow/sequence diagram, and product screenshots — and whether they
already exist. Step 1 only *discovered* existing diagrams; this stage **generates the
missing ones** by invoking the sibling skills:

- **Diagrams** → invoke the `arch-diagram` skill (`diagram-architect`) for any figure
  the post needs that isn't already in `docs/architecture/`. Pick the right **type**
  (system/sequence/data-flow/…) and **mode** (`structural` for a component map,
  `conceptual` for a trust-boundary / "where data is encrypted" figure — the blog's
  security section needed conceptual). It renders **and self-verifies** the diagram.
- **Screenshots** → invoke the `capture-screenshots` skill for any product UI the post
  shows (playground, admin console, etc.). It captures **and runs the redaction
  pipeline** (PII/secret detection → blur/mask → verify) so nothing sensitive ships;
  only the redacted image is written.

**Timing — the skill decides.** These only need the repo model + topic, so they can run
**in parallel with the writer** (Step 3) to save time. Run them **before** the writer
instead when the prose needs to reference *specific* figures by name/number. Either
way, assets must exist before the editor embeds them (Step 6).

**Degrade gracefully (§A8).** If capture is blocked (a classifier denial, or an
auth-gated page the skill shouldn't log into) or diagram export tooling is unavailable,
fall back to the documented manual path — ask the user to supply the image, or hand off
the exact command — rather than stalling. Don't invent a screenshot or a diagram that
wasn't produced.

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

Spawn `blog-editor` with the draft + fact-checker cuts + reviewer notes + any
`style_prefs` (Step 2). It produces the **final** polished post: applies the notes,
ensures every fact-checker correction landed, embeds the architecture diagrams (Step 1)
at the right points, adds front-matter (title, date, tags, summary), and runs its
editorial passes — terminology consistency, a **sparing emphasis pass** (bold the
load-bearing claim per section), the style prefs (e.g. no em-dashes), and
front-matter↔body consistency.

## Step 6.5 — Finalize checks (parallel analysis, serialized apply)

Once the editor's post exists, the remaining pre-publish work is **independent** and
fans out — spawn these **in a single message (parallel)**, the same way
`pre-push-review` fans out its dimensions. They only need the finished post; none
depends on another's output:

- `blog-final-polish` — the mechanical gate the editor's prose-eye misses: **single-H1 /
  accessibility** (a body `# ` duplicates the front-matter title's H1), **ending is a
  takeaway + CTA** (not a bare link list), **no duplicated/leftover artifacts** (doubled
  CTA lines, stray `[src:]` markers), **emphasis sanity** (neither zero nor over-bolded).
- `blog-platform-lint` (only if the target is external) — platform mechanics: **>4 tags**
  (Dev.to hard-caps at 4), **SVG/relative images** that won't render, **missing/stale
  cover**, the draft→publish flow.
- **Cover generation** (only if `cover_image` is empty) — `scripts/make-cover.py` (a
  script, not an agent) can run concurrently; **view the rendered PNG** to verify.

**Converge, then apply serially.** Because both `blog-final-polish` and
`blog-platform-lint` may *edit the same post file*, collect all their findings first,
then apply the edits **one at a time** (never let two agents write the file
concurrently — that races). Act on anything marked needs-author before publishing.

> **Dependency graph (what's sequential vs. parallel):** the content chain
> writer → fact-checker → reviewer → editor is strictly **sequential** (each transforms
> the prior, and the fact-checker is a hard gate). Everything after the editor —
> final-polish, platform-lint, cover-gen — is **independent and runs in parallel**, then
> results converge before Step 8. Publish (Step 8) and promo (Step 10) are sequential
> again: platform-lint must clear before posting, and promo needs a published URL.

## Step 7 — Write outputs

- Write the final post to `docs/blog/<slug>.md` (§A4; merge/revise if the slug exists,
  §A7).
- Write **publish-ready copies to the scratchpad**: the Markdown, and a standalone HTML
  render. Prefer a **self-contained** HTML — images inlined as `data:` URIs — so the
  page renders anywhere with no broken links and can be shared/opened directly (this
  was the single most useful "review it like a blog before posting" artifact). Use
  `pandoc` if on PATH; if absent, note that only Markdown was produced.
- **Image paths — mind the publish target.** In-repo Markdown uses repo-relative links
  (`./images/…`, `../architecture/…`) that render on GitHub. But **most external
  platforms (Dev.to, Medium, generic CMS) can't resolve them** — they need absolute
  URLs or platform-uploaded images. When the target is external, flag every relative
  image path and either rewrite to absolute (e.g. raw GitHub URLs) or note that the
  images must be uploaded to the platform. (The Dev.to REST poster in Step 8 handles
  the upload automatically; other targets do not.) Don't ship a post whose images will
  silently 404 for readers.

## Step 8 — Optional poster

The Step 6.5 checks have already run: `blog-platform-lint`'s findings are in hand and a
cover was generated if one was missing. **Apply the remaining asset prep** the lint
called for before posting:
- **Rasterize any SVG diagrams** the post references (Dev.to won't render SVG inline):
  `scripts/rasterize-svg.py IN.svg OUT.png --width 1200` (the ~1200px width matters —
  larger can silently fail the platform's image proxy). Repoint the post at the PNGs and
  host them where the platform can fetch them (absolute URLs).
- **Cover:** on a re-publish, remember Dev.to caches the cover by URL — a changed cover
  needs a **new filename** to bust the cache (`cover-v2.png`).
- Resolve every platform-lint **must-fix** before posting.

Then detect a publishing MCP (§A5) — a CMS / Dev.to / Medium / Notion connector, etc. If
one is connected **and the user opts in**, spawn `blog-poster` to create a **draft**
on that platform (never auto-publish without explicit confirmation).

If no MCP is connected but the target is **Dev.to** and the user opts in, `blog-poster`
has a direct-REST fallback: `scripts/publish-devto.py <post.md>` creates a draft via
the Dev.to API (uploads local images to Dev.to's CDN, forces `published: false`,
idempotent re-runs). It needs a `DEVTO_API_KEY` — exported, or in `~/.config/nj-agents/.env`
(the legacy `~/.claude/.env` is still read for existing installs)
(Dev.to → Settings → Extensions → "DEV Community API Keys"). If neither path applies,
stop here and hand the user the publish-ready MD/HTML files with manual posting
instructions.

## Step 9 — Propose the commit (opt-in; the artifact is the real deliverable)

The publish-ready files (and the published artifact/HTML, if one was made) are the
deliverable on their own — a git commit is **optional and never assumed**. Some
projects/users deliberately keep blog output out of git; if the user has said so, or
you're unsure, stop after handing over the files and **do not** propose a commit.

If a commit IS wanted, per `CONVENTIONS-authoring.md §A3`, scope it to *exactly* the
blog artefacts you created/changed — the post plus the assets it references
(screenshots, diagrams) — and nothing else:
```bash
# stage only the blog files you touched — list them explicitly, never `git add docs/`
git add docs/blog/<slug>.md docs/blog/images/<...> docs/architecture/<diagram>.svg
git commit -m "docs: add technical blog — <title>"
```
- **Never `git add` a whole directory** — this session swept an entire `docs/` tree
  (unrelated screenshots, a stale excalidraw source, a design note) into one commit.
  Stage the specific files, and if the post references images, include exactly those.
- **Do not propose `git push`** and do not offer to open a PR — the user pushes when
  they choose. Never run git yourself.

Summarize: the post's angle, where it landed (files + artifact URL if published), the
publish-ready files, how many fact-check iterations it took, and any claim that was
cut for being unverifiable.

## Step 10 — Optional promo copy (social-post)

Once the post is **published** and you have a live URL, offer to draft promotional copy
via the `social-post` skill/agent. Pass the published URL + the same `style_prefs`. It
returns ready-to-paste LinkedIn/X variants (short / medium / builder-story), gets the
hook and link-preview ordering right, keeps hashtags clean, and provides a first-comment
block for secondary links. It drafts only — the user posts. Skip if the user doesn't want
promo copy.
