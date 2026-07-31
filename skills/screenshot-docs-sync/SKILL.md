---
name: screenshot-docs-sync
description: Use this skill when the user asks to "update the docs with screenshots", "sync the docs after this change", "refresh the docs", "re-screenshot the docs", or wants documentation kept current as the app's UI changes over time. Detects what changed since the docs were last updated, captures fresh screenshots of the affected UI with a headless browser, and edits the relevant doc sections in place. Works in any repo with a web frontend — nothing here is specific to one project.
version: 0.1.0
class: authoring
author: navjyotnishant
---

# Screenshot + Docs Sync (authoring)

Keeps a project's documentation (and any screenshots embedded in it) in sync
with the actual running app, by diffing since the last doc update, capturing
only what changed, and editing docs in place — repeatable every time the user
makes a change, in any repo.

This is an **authoring-class** skill — follow `CONVENTIONS-authoring.md` (repo
ingest §A1, scoped output §A2, propose-commit §A3, placement §A4, MCP-detect §A5,
grounding/safety §A6, idempotent/non-clobber §A7, degrade-when-denied §A8). It
**writes** doc edits and images, then **proposes** the commit — it never runs
`git add`/`commit`/`push`.

**Related but distinct:** `/capture-screenshots` captures and redacts a *single*
set of images on request. This skill is the *maintenance* loop — it works out
which docs went stale as the UI changed, and refreshes only those. Reach for
`/capture-screenshots` when you want images; reach for this when the docs have
drifted behind the app.

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

## Dependencies

Detected at runtime, never installed by this skill (`§A5`).

| Tool | Used for | Without it |
|---|---|---|
| `npx` + Playwright | driving a headless browser to capture the UI | no capture is possible — say so and stop rather than inventing images |
| `sharp` (via `npx`) | cropping/resizing a capture to the region the doc shows | ships the full-page capture instead, noting it was not cropped |

**Screenshots of a real app can contain real data.** Anything captured here goes
through the same redaction discipline as `/capture-screenshots`: detect PII and
secrets, blur or mask them, and **verify coverage before writing**. An
un-redacted capture is never committed.

This is a **procedure**, not a fixed script: every repo has different doc
locations, launch commands, and auth. Discover these each run rather than
assuming a prior repo's answers apply here. Once discovered, note them in the
doc's own frontmatter or a comment so later runs don't re-derive from scratch
(see "Remembering what you learned" below).

## Step 1 — Find the documentation

Look for, in order: a `docs/` directory (Docusaurus/MkDocs/plain markdown), a
`README.md` with substantial content, or any `*.md` under a `wiki/` or
`documentation/` folder. If nothing matches and the user hasn't pointed you at
a location, ask where docs live before doing anything else — do not invent a
new docs structure unprompted.

Within the docs, identify which files describe UI/screens (as opposed to
architecture/API-only docs) — these are the candidates for screenshots.

## Step 2 — Figure out what changed

```bash
git log -1 --format=%H -- <doc-file>       # when was this doc last touched
git diff <that-commit>..HEAD --stat        # what changed in the app since
```

Filter the diff to frontend/UI-relevant paths (component files, pages, routes,
styles — language-specific: `src/pages`, `src/components`, `app/`, `views/`,
etc., whatever this repo uses). Ignore backend-only, test-only, and
docs-only diffs — those don't need new screenshots.

For each changed UI file, check whether the docs already reference it (a
file-path citation, a component name, a described flow). If a clear mapping
exists, that doc section needs a refresh. If a change doesn't map to any
existing doc section:
- If it looks like a new user-facing feature worth documenting, ask the user
  whether to add a new section, rather than silently inventing one.
- If it's a minor/internal change, skip it — not everything needs a screenshot.

**Auto-detection is the default (don't ask the user to pick pages every time),
but always tell them what you determined needs updating before proceeding**,
so they can redirect you if the mapping is wrong.

## Step 3 — Get the app running

Prefer, in order:
1. A project-specific launch mechanism already documented (a `run` skill, a
   `justfile`/`Makefile` target, a `docker-compose up` instruction in
   CLAUDE.md/AGENTS.md/README).
2. The project's own dev-server script (`npm run dev`, `pnpm dev`, etc.) —
   check `package.json` scripts.

Confirm the app is actually reachable (`curl -s -o /dev/null -w "%{http_code}"
<url>`) before proceeding. Don't assume a server is already up.

## Step 4 — Handle authentication

Only relevant if the screens you need are behind a login. Check for a
documented way in, in order:
1. A seeded dev/admin user or a documented "insert a session directly into
   the dev database" trick (some apps support this for local testing —
   look for it in CLAUDE.md/AGENTS.md/docs before assuming one exists).
2. An env var the app already honors for a bearer token / API key in dev mode.
3. A `.env.example` or setup doc showing test credentials.

If none of these exist, **stop and ask the user** how they'd like you to
authenticate — do not fabricate credentials, do not attempt to guess a
password, and do not skip auth by modifying the app's auth code.

Never hardcode discovered credentials/tokens into the doc-sync scaffold you
write in Step 6 — mint short-lived sessions per run and revoke/clean them up
afterward if the mechanism supports it.

## Step 5 — Capture screenshots

Use a headless browser (Playwright is a safe default: `npm install playwright
&& npx playwright install chromium`, run from a scratchpad/temp directory —
**do not add it as a project dependency** unless the user asks).

Practical capture technique notes learned from real use:
- Inject auth via `page.addInitScript` writing to `localStorage`/cookies
  *before* navigation, rather than driving a login form — faster and more
  reliable if a token-based method is available (see Step 4).
- Wait for `networkidle` plus a short fixed delay (canvas/chart libraries
  like React Flow often need an extra ~1–2s after network idle to finish
  layout/animation).
- For a single component/panel rather than the full viewport, target it with
  a stable CSS selector (a distinctive class or `data-testid`) and use
  Playwright's element-level `.screenshot()` rather than capturing the full
  page and cropping externally — sharper, and doesn't depend on an image
  library being installed.
- Prefer clicking near a control's edge/corner rather than its label text
  when the label itself has its own click handler (e.g. double-click-to-rename
  fields) — avoids accidentally triggering unrelated UI state.
- Use a wide, consistent viewport (e.g. 1600×1000) across a doc's screenshots
  so they read as one series, not mismatched sizes.

Save into the docs' existing static-asset convention (e.g.
`docs/static/img/<section>/` for Docusaurus) rather than inventing a new
location.

## Step 6 — Update the docs

Edit the relevant section(s) in place:
- Replace outdated screenshots at their existing embed path (same filename,
  overwritten) if the layout is materially the same — keeps the diff small
  and doesn't leave orphaned image files.
- If the UI changed enough that the old screenshot's filename/description no
  longer fits, add a new image and remove the stale one and its markdown
  reference together.
- Update the surrounding prose to match what's actually on screen now (field
  names, button labels, section order) — a stale screenshot next to stale
  prose compounds the problem.
- Write real alt text describing what the image actually shows, not a generic
  caption.

## Step 7 — Clean up

- Revoke any temporary auth session/token minted in Step 4.
- Leave no capture scripts or scratch files inside the project repo — they
  belong in the scratchpad/temp directory only, per this environment's own
  conventions.
- Report a short summary: what changed, which doc sections/screenshots were
  updated, and anything skipped that the user should review manually.

## Step 8 — Propose the commit (never run it)

Per `CONVENTIONS-authoring.md §A3`: show `git status --short` and
`git diff --stat`, confirm only the intended docs and images are staged, then
**print** the commands for the user to run:

```bash
git add <the doc files and images you updated>
git commit -m "docs: refresh screenshots after <what changed>"
git push
```

Never run git yourself. Call out anything unexpected in the staged set rather
than committing it — a stray capture or a scratch file is exactly what this
step exists to catch.

## Remembering what you learned (optional, speeds up future runs)

If this repo doesn't already document its launch command / docs location /
auth method clearly, consider proposing (not silently adding) a short note to
CLAUDE.md/AGENTS.md once you've worked it out, so re-running this skill later
— or a different agent — doesn't have to rediscover it. Only add such a note
with the user's go-ahead, since it's a durable repo change, not a one-off
scratch action.
