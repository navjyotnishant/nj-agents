---
name: changelog
description: Use this skill when the user asks to "update the changelog", "generate a CHANGELOG", "cut release notes", "summarize what changed since the last release/tag", or wants a human-readable record of changes in an industry-standard format. Generates or updates CHANGELOG.md using the Keep a Changelog format + Semantic Versioning, reading Conventional Commits as the input signal, then PROPOSES the commit (never commits, pushes, or tags). Works in any git repo; nothing here is project-specific.
version: 0.1.0
class: authoring
author: Navjyot Nishant
---

# Changelog (authoring)

Generates or updates a `CHANGELOG.md` in the **Keep a Changelog** format
(keepachangelog.com) with **Semantic Versioning**, driven by **Conventional
Commits** where present. It **writes the file** but only **proposes** the commit —
it never runs `git add`/`commit`/`push`/`tag`.

This is an **authoring-class** skill — follow `CONVENTIONS-authoring.md` (repo
ingest §A1, authoring output §A2, propose-commit §A3, placement §A4, MCP-detect §A5,
grounding/safety §A6, idempotent/non-clobber §A7).

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
> attributable to a named stage (`§R`).

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  CHANGELOG — AUTHORING                                            ║
╠══════════════════════════════════════════════════════════════════╣
║  Generates/updates CHANGELOG.md (Keep a Changelog + SemVer) from  ║
║  your commit history, then PROPOSES the commit. It writes the     ║
║  changelog file but never runs git add / commit / push / tag —    ║
║  you review the diff and run the commands yourself.               ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **Commit history** to summarize since the last release/changelog entry. If there's
  nothing new, report "changelog already up to date" and stop.
- **No API key / no network.** `gh` (GitHub CLI) is used *only if present* to enrich
  with merged-PR titles (§A5) — absent, commits-only.

## Step 1 — Ingest light repo context

Per `CONVENTIONS-authoring.md §A1`, just enough for the project name and tone (name,
purpose, whether it already uses Conventional Commits / has releases).

## Step 2 — Determine the range to summarize

- If a `CHANGELOG.md` exists, summarize commits **since its latest documented
  version** (or extend its existing `[Unreleased]` section).
- Else, since the **last git tag**: `git describe --tags --abbrev=0` → range
  `<tag>..HEAD`.
- Else (no tags, no changelog): the full history (`HEAD`), noting it's an initial
  changelog.

Collect subjects + bodies:
```bash
git log <range> --no-merges --format='%H%x09%s%x09%b'
```
If `gh` is on PATH and the repo has a GitHub remote, optionally enrich with merged-PR
titles for the range (§A5). Degrade to commits-only if `gh` is absent or unauthenticated.

## Step 3 — Detect existing CHANGELOG (merge, don't clobber)

- **Exists** → parse it; you will **merge** new entries into the `[Unreleased]`
  section (create one if missing), never rewriting already-released sections (§A7).
- **Absent** → create a fresh file with the standard Keep a Changelog header
  (intro line + the "format is based on Keep a Changelog / adheres to SemVer" note)
  and an `[Unreleased]` section.

## Step 4 — Compute the suggested version bump

Parse Conventional Commit prefixes across the range:
- `feat:` → **minor**
- `fix:` / `perf:` → **patch**
- any `!` (e.g. `feat!:`) or `BREAKING CHANGE:` in a body → **major**
- `docs:`/`chore:`/`refactor:`/`test:`/`build:`/`ci:`/`style:` → no user-facing bump
  on their own (still summarized where relevant, e.g. `refactor` usually omitted).

Present the suggested bump (e.g. "18 commits since v1.2.0 → suggest **v1.3.0**
(minor: 3 feats, 5 fixes)") and **let the user override**. If history isn't
conventional, fall back to keyword/heuristic grouping and ask the user for the
version.

## Step 5 — Spawn the changelog-writer agent

Spawn `changelog-writer` with the collected commits (and PR titles) grouped by the
Keep a Changelog categories — **Added / Changed / Deprecated / Removed / Fixed /
Security**. It returns clean, de-duplicated, user-facing entries (terse subjects
rewritten into prose; `wip`/`merge`/`fixup`/format-only noise dropped).

## Step 6 — Write / merge the changelog

Write the returned section per `CONVENTIONS-authoring.md §A4`/§A7:
- Under `[Unreleased]` (default), or under a new `## [x.y.z] - YYYY-MM-DD` section if
  the user is cutting that version now.
- Keep only non-empty category subheadings.
- Maintain the version-comparison **link references** at the bottom of the file
  (`[Unreleased]: <repo>/compare/vX.Y.Z...HEAD`, `[x.y.z]: .../compare/...`), derived
  from the git remote URL when available.

## Step 7 — Propose the commit (never run it)

Per `CONVENTIONS-authoring.md §A3`: show `git status --short`, `git diff --stat`, and
the diff of `CHANGELOG.md`, then print:

```bash
git add CHANGELOG.md
git commit -m "docs: update changelog"
git push
```

If (and only if) the user is cutting a release, also print — clearly marked as a
**release-only** action to run manually:

```bash
# release only — run when you actually cut vX.Y.Z:
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

Never run any of these. Summarize what was written, the suggested version, and
anything skipped (e.g. non-conventional commits grouped heuristically).
