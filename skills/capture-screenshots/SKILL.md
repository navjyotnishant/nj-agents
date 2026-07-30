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
> so `§C` (cost) and `§R` (progress reporting) apply. **Cost shape:** a 3-agent pipeline (capturer → sensitive-data-reviewer → redactor).
> State it and get a yes before the first dispatch; cap fix rounds at 2; halt on any
> signal to stop. Announce the **pipeline** up front and each stage as it starts, so a stall is
> attributable to a named stage (`§R`).

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
- **No external API.** All analysis is done by this Claude session + subagents.

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

## Step 3 — Capture (raw → gitignored dir)

Spawn `screenshot-capturer` for the chosen source. Raw captures are written to a
**gitignored** `.screenshots-raw/` dir at the repo root (propose adding
`.screenshots-raw/` to `.gitignore` per §A7 if not already ignored — do not proceed
to commit anything while the raw dir is untracked-and-not-ignored). Use a consistent
viewport for web (e.g. 1600×1000); target elements by stable selector for component
shots.

**Two constraints from real runs — plan for them, don't fail on them:**
- **The capturer subagent can be blocked** (a sandbox/permission classifier may deny a
  browser subagent that loads a live external URL). If the spawn is denied, fall back
  to driving the **browser tool directly** from the skill, or — if that's blocked too
  — hand the user the exact URL/viewport and ask them to supply the image (then treat
  it as source `existing`). A denial is a redirect, not a dead end.
- **The browser tool can usually only write under the repo root** (Playwright's
  allowed-roots). If a capture to `.screenshots-raw/` (or a scratch path) is refused,
  write to an allowed path under the repo, then move the file into the gitignored raw
  dir. Don't let a write-root refusal abort the capture.

**Auth-gated targets — offer "you capture, I redact."** If the page is behind login
and no legitimate dev credential exists (Step 2), do NOT try to obtain or fabricate one
and do NOT drive a separate unauthenticated browser expecting the user's session — a
fresh browser has no session and lands on the login page. Instead offer: the user
captures the authenticated screen themselves and gives you the file (source
`existing`), and the pipeline still runs detection → redaction → verify on it. This
keeps credentials on the user's machine and still delivers a safe, redacted image.

## Step 4 — Detect sensitive data (mark regions)

Spawn `sensitive-data-reviewer` on each raw image. It identifies PII/secrets —
emails, API keys/tokens, passwords, phone numbers, credit-card/SSN numbers, personal
names, physical addresses, internal hostnames/IPs — and returns, for each, a
**bounding region** (x, y, w, h) plus a **risk class** (`high` = tokens/keys/cards/
SSN; `low` = illustrative emails/names) and the recommended blur style.

## Step 5 — Redact (blur/mask) + verify gate

Spawn `screenshot-redactor` with the raw image + marked regions. Using `sharp`/`jimp`
(extract region → blur/box → composite back), it applies, **by default**:
- **Full blur / solid box** for `high`-risk regions (unrecoverable).
- **Half/partial mask** for `low`-risk illustrative regions (e.g. `j***@example.com`).
- **Placeholder substitution** for `low`-risk illustrative regions in a blog/marketing
  shot: overlay a realistic fake (a real email → `demo-admin@example.com`) instead of a
  blur box. It reads far more naturally in a polished screenshot than a black bar, and
  the real value is still gone. Only for low-risk data, and only when the region is
  clean enough to cover fully — never for high-risk secrets.

Then it **verifies coverage** — confirms every flagged region is actually obscured in
the output. **This is a hard gate:** if any flagged region's coverage can't be
verified (low-res text, ambiguous bounds, a region that shifted), **do not write the
image to docs.** Report what's uncertain and let the user resolve (re-run, wider
blur, or manual fix). Safe-by-default: a miss stays uncommitted.

## Step 6 — Confirm redactions with the user (interactive)

Show a before/after and a **list of every region redacted** (what type, which style).
The user can confirm, unblur a false positive, or ask for more. In non-interactive
mode, keep everything redacted (never auto-unblur).

## Step 7 — Write redacted image(s) + placement

Write **only the redacted** image(s) per `CONVENTIONS-authoring.md §A4` — an existing
images dir, else `docs/images/` (or `docs/blog/images/` if for a blog). Never write
the raw/un-redacted version into a committed path. Report the chosen path.

## Step 8 — Propose the commit (never run it)

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
