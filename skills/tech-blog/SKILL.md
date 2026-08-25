---
name: tech-blog
description: Use this skill when the user asks to "write a technical blog about this project", "draft a blog post explaining the architecture", "write an engineering article about what we built", or wants an expert-level technical write-up of the project. Runs a multi-agent pipeline (writer → fact-checker → reviewer → editor → optional poster), grounds every claim in the actual repo (the fact-checker BLOCKS on anything it can't verify), embeds architecture diagrams if present, writes the post to docs/blog/, and produces publish-ready Markdown + HTML. Posts via an MCP only if one is connected and you opt in. Works in any git repo; nothing here is project-specific.
version: 0.2.0
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
> so `§C` (cost) and `§R` (progress reporting) apply. **Cost shape:** a 6-agent pipeline (writer → fact-checker → reviewer → editor → final-polish → platform-lint),
> plus one extra writer+fact-checker round per fact-check retry (capped at 2, `§C`).
> State it and get a yes before the first dispatch; cap fix rounds at 2; halt on any
> signal to stop. Announce the **pipeline** up front and each stage as it starts, so a stall is
> attributable to a named stage (`§R`). Steps 3–6.5 (the sequential content chain plus
> the parallel finalize checks) run as a **`Workflow`-tool pipeline** — everything
> before it (repo ingest, topic/asset prep) and after it (writing outputs, posting,
> commit, promo) involves cross-skill invocation, git, or external opt-in and stays
> outside the script, same split `/pre-push-review` uses.


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

## Steps 3–6.5 — Run the Workflow pipeline

See [`docs/architecture/pipeline-tech-blog-nano.png`](../../docs/architecture/pipeline-tech-blog-nano.png)
for the Draft (with its retry loop) → Refine → Finalize shape at a glance.

Once the topic/angle/audience/voice/`style_prefs` are confirmed (Step 2) and the
visual assets are ready or in flight (Step 2.5), hand this script to the `Workflow`
tool. It covers the sequential content chain (writer → fact-check-loop → reviewer →
editor) and the parallel finalize checks — everything before and after this stays
outside the script (repo ingest, asset generation via sibling skills, writing
outputs, posting, commit, promo), since none of that is agent orchestration this
tool models.

```js
export const meta = {
  name: 'tech-blog',
  description: 'Sequential content chain with a bounded fact-check retry loop, then parallel finalize checks',
  phases: [
    { title: 'Draft', detail: 'writer, then fact-check retry loop (max 2 rounds)' },
    { title: 'Refine', detail: 'reviewer, then editor' },
    { title: 'Finalize', detail: 'final-polish + platform-lint + cover-gen in parallel' },
  ],
}

// Every agent() call below carries an explicit schema. Without one, an agent
// returns free-form prose — and a live test of this exact pipeline (no schemas)
// showed the failure mode directly: blog-fact-checker's own internal reasoning
// ("I retract the wrong verdict on that line...") got concatenated into the next
// stage's prompt as if it were blog content, and every downstream stage correctly
// flagged the input as garbled rather than producing useful output. A schema
// forces the agent to return the field the NEXT stage actually needs, not its
// reasoning trail.
const DRAFT_SCHEMA = { type: 'object', properties: {
  markdown: { type: 'string' }, citations: { type: 'array', items: { type: 'string' } },
}, required: ['markdown'] }
const FACT_CHECK_SCHEMA = { type: 'object', properties: {
  verdict: { type: 'string', enum: ['PASS', 'BLOCK'] },
  claims: { type: 'array', items: { type: 'object', properties: {
    claim: { type: 'string' }, location: { type: 'string' },
    status: { type: 'string', enum: ['verified', 'unverifiable', 'wrong'] },
    evidence: { type: 'string' },
  } } },
}, required: ['verdict', 'claims'] }
const REVIEWER_SCHEMA = { type: 'object', properties: {
  notes: { type: 'array', items: { type: 'object', properties: {
    location: { type: 'string' }, issue: { type: 'string' }, suggestion: { type: 'string' },
    priority: { type: 'string', enum: ['must-fix', 'nice-to-have'] },
  } } },
}, required: ['notes'] }
const EDITOR_SCHEMA = { type: 'object', properties: {
  markdown: { type: 'string' }, notes: { type: 'string' },
}, required: ['markdown'] }
const CHECKLIST_SCHEMA = { type: 'object', properties: {
  verdict: { type: 'string' },
  items: { type: 'array', items: { type: 'object', properties: {
    item: { type: 'string' }, status: { type: 'string' }, detail: { type: 'string' },
  } } },
  fixedMarkdown: { type: 'string' },
}, required: ['verdict', 'items'] }

const MAX_FACT_CHECK_ROUNDS = 2 // §C's fix-round cap — a draft that still has
                                 // wrong/unverifiable claims after 2 rounds stops
                                 // here and hands the unresolved list back to the
                                 // user rather than looping indefinitely.

phase('Draft')
let draft = await agent(
  buildWriterPrompt(repoModel, topic, angle, audience, voice),
  { agentType: 'blog-writer', schema: DRAFT_SCHEMA }
)

let factCheck = null
for (let round = 1; round <= MAX_FACT_CHECK_ROUNDS; round++) {
  log(`fact-check round ${round}/${MAX_FACT_CHECK_ROUNDS}`)
  factCheck = await agent(
    buildFactCheckPrompt(draft.markdown),
    { agentType: 'blog-fact-checker', schema: FACT_CHECK_SCHEMA }
  )
  if (factCheck.verdict === 'PASS') break
  if (round === MAX_FACT_CHECK_ROUNDS) break // exhausted retries, stop looping
  draft = await agent(
    buildWriterFixPrompt(draft.markdown, factCheck.claims),
    { agentType: 'blog-writer', schema: DRAFT_SCHEMA }
  )
}

phase('Refine')
const reviewerNotes = await agent(
  buildReviewerPrompt(draft.markdown),
  { agentType: 'blog-reviewer', schema: REVIEWER_SCHEMA }
)
const edited = await agent(
  buildEditorPrompt(draft.markdown, factCheck, reviewerNotes.notes, stylePrefs, diagrams),
  { agentType: 'blog-editor', schema: EDITOR_SCHEMA }
)

phase('Finalize')
// blog-final-polish and blog-platform-lint both ANALYZE the same finished post —
// neither writes to it, so running them concurrently is safe. The actual file
// edits (Step 6.5's original "converge, then apply serially" rule) still happen
// afterward, outside this script, one at a time, once both sets of findings are
// in hand — parallelizing the analysis was always safe; it was only the EDITS
// that needed serializing, and those aren't part of this script.
const finalizeChecks = [
  () => agent(buildFinalPolishPrompt(edited.markdown), { agentType: 'blog-final-polish', schema: CHECKLIST_SCHEMA }),
]
if (targetIsExternal) {
  finalizeChecks.push(() => agent(buildPlatformLintPrompt(edited.markdown), { agentType: 'blog-platform-lint', schema: CHECKLIST_SCHEMA }))
}
const [finalPolish, platformLint] = await parallel(finalizeChecks)

return { draft: edited.markdown, factCheck, reviewerNotes: reviewerNotes.notes, finalPolish, platformLint: platformLint ?? null }
```

The pipeline **spawns `blog-writer`** (Draft phase, and again per fact-check retry),
**spawns `blog-fact-checker`** (Draft phase, the hard gate), **spawns
`blog-reviewer`** and **spawns `blog-editor`** (Refine phase), and **spawns
`blog-final-polish`** plus, when the target is external, **spawns
`blog-platform-lint`** (Finalize phase, in parallel — analysis only, no file
writes). Cover generation (`scripts/make-cover.py`) is a script, not an agent, and
can still run concurrently with the Finalize phase outside this script — **view the
rendered PNG** to verify before using it.

**Any `wrong` or `unverifiable` claim keeps the loop going** (up to
`MAX_FACT_CHECK_ROUNDS`); a post that still has one after 2 rounds does not
finalize — report the unresolved claims to the user rather than shipping with a
gate silently overridden (§A6, unchanged from before this migration). This is a
bounded retry `while`-style loop, not `pipeline()`'s one-pass-per-item shape,
because the same draft is re-checked in place rather than moving through distinct
items.

**Converge, then apply serially — still true, still outside the script.** Because
both `blog-final-polish` and `blog-platform-lint` findings may call for *edits to
the same post file*, collect both sets of findings (the script's return value
already has them together) before touching the file, then apply the edits **one at
a time** — never let two edits race on the same file. Act on anything marked
needs-author before publishing.

> **Dependency graph (what's sequential vs. parallel):** the content chain
> writer → fact-check-loop → reviewer → editor is strictly **sequential** (each
> transforms the prior, and the fact-checker is a hard gate — modeled as a bounded
> retry loop, not a single pipeline stage). The Finalize phase — final-polish,
> platform-lint — is **independent and runs in parallel** inside the script (analysis
> only); the *file edits* those findings call for still converge and apply serially
> outside it. Publish (Step 8) and promo (Step 10) are sequential again: platform-lint
> must clear before posting, and promo needs a published URL.

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
