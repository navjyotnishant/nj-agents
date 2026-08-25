---
name: capture-screenshots
description: Use this skill when the user asks to "take screenshots for the blog/docs/README", "capture the app UI", "screenshot this page/component/terminal output", or wants images of the project with sensitive data redacted. Captures from a running web app, terminal/CLI output, a static HTML/component, or existing images, then runs a redaction pipeline (detect PII/secrets → blur/mask → verify) so nothing sensitive ships. Writes redacted images into docs and PROPOSES the commit; the un-redacted original never gets committed. Works in any git repo; nothing here is project-specific.
version: 0.1.0
class: authoring
author: navjyotnishant
---

# Capture Screenshots (authoring, multi-agent)

Captures screenshots for documentation/blogs/READMEs and **redacts sensitive data**
before anything is written. A multi-agent pipeline: `screenshot-capturer` →
`sensitive-data-reviewer` → `screenshot-redactor` (with a coverage **verify gate**).
It writes only the **redacted** image into the repo and **proposes** the commit; the
raw capture stays in a gitignored dir and is never committed.

This is an **authoring-class** skill — follow `CONVENTIONS-authoring.md` (repo ingest
§A1, scoped output §A2, propose-commit §A3, placement §A4, MCP/tool-detect §A5,
grounding/safety §A6, non-clobber §A7). Redaction adds its own hard safety rules
below.

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

> **Spawning subagents — `CONVENTIONS-orchestration.md`.** This skill spawns agents
> via a `Workflow`-tool pipeline (Step 3-5), so `§C` (cost) and `§R` (progress
> reporting) apply. **Cost shape:** a 3-agent pipeline (capturer → sensitive-data-reviewer
> → redactor) per image. State it and get a yes before the first dispatch; cap fix
> rounds at 2; halt on any signal to stop. Announce the **pipeline** up front and
> each stage as it starts, so a stall is attributable to a named stage (`§R`). The
> run is resumable via `resumeFromRunId` if interrupted (`§M1`) — worth mentioning
> on a multi-image run, where a partially-completed pipeline for one image is real
> sunk cost worth preserving.


## Dependencies

Detected at runtime, never installed by this skill (`§A5`).

| Tool | Used for | Without it |
|---|---|---|
| Playwright (via `npx`) | driving a browser to capture a web page | ask for an existing image, or capture terminal/component output instead |
| `sharp` *or* `jimp` (via `npx`) | blurring and masking the flagged regions | **BLOCK** — an unredacted image must never be written |

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  CAPTURE SCREENSHOTS — AUTHORING (multi-agent)                   ║
╠══════════════════════════════════════════════════════════════════╣
║  Captures from a web app / terminal / static HTML / existing     ║
║  image, then DETECTS and REDACTS sensitive data (emails, tokens, ║
║  keys, phone, cards, names) by default before writing anything.   ║
║  Only the REDACTED image is written to docs + committed; the raw  ║
║  capture stays in a gitignored dir and is never committed. If     ║
║  redaction coverage can't be verified, nothing is written. This   ║
║  skill PROPOSES the commit — it never runs git.                  ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **Capture tooling (auto, via `npx` from a scratch dir — not added as project
  deps):** Playwright for web capture (this machine has Chromium cached; else it
  fetches once), and `sharp` (preferred) or `jimp` for blur/mask. If a tool can't run
  (§A5), degrade: capture what's possible, or ask the user for an existing image.
- **For web capture:** a way to reach the app (launch command + auth) — discovered
  per repo (Step 2). **Never fabricate credentials.**
- **No external API.** All analysis is done by this AI session + subagents.

## Step 1 — Resolve what to capture

Determine the **source** (from the user's request or ask):
- `web` — a running web app's page/route/state.
- `terminal` — command/CLI output rendered as an image.
- `static` — a standalone HTML file or an isolated component.
- `existing` — annotate/redact image(s) the user already has (skip capture).

And **what** exactly (which route/state, which command, which file, which images), and
where the images will be used (blog, README, docs) to inform placement (§A4).

## Step 2 — For web capture: discover launch + auth (never fabricate)

Per `CONVENTIONS-authoring.md §A1`/§A5, discover how to run and reach the app:
- **Launch:** a documented run command (CLAUDE.md/AGENTS.md/README), `package.json`
  scripts (`dev`/`start`), a `Makefile`/`justfile` target, or `docker-compose`.
  Confirm reachability: `curl -s -o /dev/null -w "%{http_code}" <url>`.
- **Auth (only if the target is behind login):** a seeded dev user, an env/bearer
  token the app honors in dev, or `.env.example` test creds. **If none exists, STOP
  and ask** — never fabricate a password, never modify the app's auth, never bypass
  it. Mint short-lived sessions and clean them up after.

If the app is already running and the user gives a URL (+ any auth), use that.

## Step 3 — Resolve sources, then run the Workflow pipeline

Before scripting anything, resolve **what actually gets captured** — this stays
prose, not script, since it involves real runtime fallbacks a script shouldn't own:

- **Spawn the `screenshot-capturer` agent** for the chosen source, before the
  Workflow script runs — it's a single one-shot capture per image, not a pipeline
  stage, so it stays a plain spawn in prose here. Raw captures land in a gitignored
  `.screenshots-raw/` dir at the repo root (propose adding it to `.gitignore` per
  §A7 if not already ignored — do not proceed while the raw dir is
  untracked-and-not-ignored). Use a consistent viewport for web (e.g. 1600×1000);
  target elements by stable selector for component shots.
- **The capturer subagent can be blocked** (a sandbox/permission classifier may deny
  a browser subagent that loads a live external URL). If the spawn is denied, fall
  back to driving the **browser tool directly** from the skill, or — if that's
  blocked too — hand the user the exact URL/viewport and ask them to supply the
  image (then treat it as source `existing`). Resolve this *before* the Workflow
  script runs, not inside it — a denial is a redirect, not something to retry
  in-script.
- **The browser tool can usually only write under the repo root** (Playwright's
  allowed-roots). If a capture to `.screenshots-raw/` is refused, write to an
  allowed path under the repo, then move the file into the gitignored raw dir.
- **Auth-gated targets — offer "you capture, I redact."** If the page is behind
  login and no legitimate dev credential exists (Step 2), do NOT try to obtain or
  fabricate one — offer the user captures the authenticated screen themselves and
  hands you the file (source `existing`); the pipeline below still runs detection →
  redaction → verify on it.

Once `images` (a list of raw capture paths, one per requested screenshot) is
resolved, hand this script to the `Workflow` tool. **Each image's pipeline runs
independently** — `pipeline()`, not a synchronized barrier per stage — so a slow
image's detect/redact never blocks a fast one:

```js
export const meta = {
  name: 'capture-screenshots',
  description: 'Per-image capture->detect->redact pipeline, independent per image',
  phases: [
    { title: 'Detect', detail: 'sensitive-data-reviewer per image' },
    { title: 'Redact', detail: 'screenshot-redactor per image, verify gate' },
  ],
}

// screenshot-capturer already ran (Step 3's prose, above) — each entry in `images`
// is a path to a raw capture already on disk. This script picks up from detection.
const DETECT_SCHEMA = { type: 'object', properties: {
  regions: { type: 'array', items: { type: 'object', properties: {
    x: { type: 'number' }, y: { type: 'number' }, w: { type: 'number' }, h: { type: 'number' },
    type: { type: 'string' }, risk: { type: 'string', enum: ['high', 'low'] },
    blur_style: { type: 'string', enum: ['full', 'partial'] },
  } } },
  summary: { type: 'string' },
}, required: ['regions'] }
const REDACT_SCHEMA = { type: 'object', properties: {
  verdict: { type: 'string', enum: ['PASS', 'BLOCK'] },
  redacted_path: { type: 'string' },
  regions: { type: 'array', items: { type: 'object', properties: {
    type: { type: 'string' }, risk: { type: 'string' }, style_applied: { type: 'string' }, verified: { type: 'boolean' },
  } } },
  blocked_reason: { type: 'string' },
}, required: ['verdict', 'regions'] }

const results = await pipeline(
  images,
  imagePath => agent(
    `Identify sensitive regions in this image: ${imagePath}. Flag emails, API keys/tokens, passwords, phone numbers, credit-card/SSN numbers, personal names, physical addresses, internal hostnames/IPs. For each, return a bounding region (x,y,w,h), risk class (high = secrets/cards/SSN, low = illustrative), and recommended blur_style (full for high, partial allowed for low).`,
    { label: `detect:${imagePath}`, phase: 'Detect', agentType: 'sensitive-data-reviewer', schema: DETECT_SCHEMA }
  ),
  (detected, imagePath) => agent(
    `Redact this image: ${imagePath}, using these flagged regions: ${JSON.stringify(detected?.regions ?? [])}. Full blur for high-risk regions, partial mask (or placeholder substitution for illustrative low-risk data) for low-risk. Then VERIFY every flagged region is actually obscured before returning PASS — if any region's coverage can't be verified, return BLOCK with the reason, and do not produce a path for writing.`,
    { label: `redact:${imagePath}`, phase: 'Redact', agentType: 'screenshot-redactor', schema: REDACT_SCHEMA }
  )
)

return { results: results.map((r, i) => ({ image: images[i], ...r })) }
```

The pipeline **spawns `sensitive-data-reviewer`** (Detect phase) and **spawns
`screenshot-redactor`** (Redact phase, the hard verify gate) per image.
`screenshot-capturer` runs *before* this script, in Step 3's prose above, since its
real-world fallback behavior (blocked spawn, write-root refusal, auth-gating) is
runtime degradation logic a Workflow script shouldn't own — the script picks up
once raw captures already exist on disk.

**This is a hard gate, unchanged by the migration:** if `verdict` comes back
`BLOCK` for any image, **do not write that image to docs.** Report what's
uncertain (`blocked_reason`) and let the user resolve (re-run, wider blur, manual
fix). Safe-by-default: a miss stays uncommitted — this was always `nj-run`-free,
plain-JS logic reading the script's own return value, not a separate gate to
maintain.

## Step 4 — Confirm redactions with the user (interactive)

Show a before/after and a **list of every region redacted** (what type, which style).
The user can confirm, unblur a false positive, or ask for more. In non-interactive
mode, keep everything redacted (never auto-unblur).

## Step 5 — Write redacted image(s) + placement

Write **only the redacted** image(s) per `CONVENTIONS-authoring.md §A4` — an existing
images dir, else `docs/images/` (or `docs/blog/images/` if for a blog). Never write
the raw/un-redacted version into a committed path. Report the chosen path.

## Step 6 — Propose the commit (never run it)

Per §A3, show `git status`/diff of the **redacted images only** and print:
```bash
git add docs/images/<name>.png
git commit -m "docs: add screenshots"
git push
```
Confirm `.screenshots-raw/` is gitignored so no raw capture is committed. Summarize:
what was captured, how many regions were redacted (by risk class), anything the
verify gate blocked, and where the images landed.

## Redaction safety rules (hard)

- **The un-redacted original is never committed.** It lives only in the gitignored
  `.screenshots-raw/` (or scratchpad); the repo only ever gets the redacted version.
- **Redact by default.** Everything the reviewer flags is redacted unless the user
  explicitly unblurs it after seeing it.
- **Verify before write.** Unverifiable coverage blocks the write (Step 5).
- **High-risk is always full-blur.** Tokens, keys, full card/SSN are never
  half-masked.
- **Never fabricate credentials / never bypass app auth** to reach a screen.
