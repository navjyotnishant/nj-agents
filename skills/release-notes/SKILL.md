---
name: release-notes
description: Use this skill when the user asks to "cut a GitHub release", "publish release notes", "draft a release for this version", or wants to turn a version's changes into a GitHub Release. It prefers an existing CHANGELOG.md section as the notes body (composing with /changelog) and otherwise summarizes the commit delta since the last tag, then drafts a `gh release create --draft` command — a DRAFT release, never published, no tag pushed on its own. Falls back to printing the notes + tag commands when `gh` is absent. Works in any git repo; nothing here is project-specific.
version: 0.1.0
class: workflow
author: navjyotnishant
---

# Release Notes (workflow)

Turns a version's changes into a **draft GitHub Release** — the release object on the
repo's Releases page, with a tag and rendered notes. This is the one release artifact
`/changelog` does **not** produce: `/changelog` writes and maintains `CHANGELOG.md`;
this skill publishes a Release from it.

**Compose with `/changelog`, don't duplicate it.** If a `CHANGELOG.md` exists, its
section for the version **is** the notes body — this skill reuses it rather than
re-summarizing. Only when there's no changelog does it summarize the commit delta
itself. If the changelog is missing or stale, it says so and points at `/changelog`.

This is a **workflow-class** skill (see `/pr-describe`, `/commit-assistant`): reads the
delta, drafts an artifact, and **proposes — never acts**. It creates a **draft**
release only; it never publishes a release and never pushes a tag on its own
(`CONVENTIONS-authoring.md §A3`). `gh` is **detected, never required** (§A5).

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
| `gh` | drafting the GitHub Release | prints the notes and the tag commands instead |

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  RELEASE-NOTES — WORKFLOW                                         ║
╠══════════════════════════════════════════════════════════════════╣
║  Turns a version's changes into a DRAFT GitHub Release, reusing   ║
║  your CHANGELOG section as the notes when present. It PROPOSES:   ║
║  a draft only — never publishes a release, never pushes a tag.    ║
║  Without gh, it prints the notes + the exact commands to run.     ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **A version to release.** Take it from the user, or infer the next tag from the
  changelog's latest version / `git describe --tags`. If ambiguous, ask — don't guess a
  version number.
- **A GitHub remote** for the actual release. `gh` (GitHub CLI) is used **only if
  present and authenticated** to draft the release (§A5). Absent → print-only fallback.

## Step 1 — Resolve the version and the prior tag

```bash
git describe --tags --abbrev=0 2>/dev/null   # last tag → the "since" point
git tag --list --sort=-v:refname | head -5   # existing tags, to avoid collisions
```

- Confirm the **target version** (e.g. `v1.3.0`) and that its tag doesn't already exist
  as a published release. If the tag exists but no release does, that's fine — you'll
  draft a release *for* the existing tag.
- Determine the **prior version** for the "full changelog" compare link.

## Step 2 — Get the notes body (prefer CHANGELOG, §A6)

**Preferred — reuse `CHANGELOG.md`:**
- Parse the section for the target version (`## [1.3.0] - …`). Use it verbatim as the
  body. This is why the skill composes with `/changelog` instead of duplicating it.
- If the version is still under `[Unreleased]`, tell the user to cut it in the changelog
  first (offer `/changelog`) — or, on their say-so, use the `[Unreleased]` content as
  the draft body and note it isn't yet a released changelog section.

**Fallback — no changelog:** summarize `"<prior-tag>..HEAD"` grouped by Conventional
Commit type (Features / Fixes / etc.), commits-only, noting the repo has no changelog
and suggesting `/changelog` for a durable record. Never invent entries (§A6);
`wip`/`merge`/`fixup` noise is dropped.

**Always append** a compare link when a GitHub remote is known:
`**Full changelog:** https://github.com/<owner>/<repo>/compare/<prior>...<version>`.

## Step 3 — Present the notes, then draft the release (opt-in, §A5)

Show the resolved version, tag, and the full notes body for review. Then, by
capability, always defaulting to the safe path:

1. **`gh` present + authenticated + GitHub remote + user opts in** → draft:
   ```bash
   gh release create <version> --draft \
     --title "<version>" \
     --notes-file <scratchpad/notes.md> \
     --target "$(git rev-parse --abbrev-ref HEAD)"
   ```
   - `--draft` **always** — never a published release, never `--latest` promotion.
   - If the tag doesn't exist yet, `gh release create` creates it **on the draft**
     (GitHub does not push a tag to the remote until the draft is published — so this
     stays a proposal). Report the draft URL and that **publishing is the user's action**
     in the GitHub UI (or a later `gh release edit <version> --draft=false`).
2. **`gh` absent / not GitHub / declined** → **print** the notes (and write them to the
   scratchpad), plus the exact commands to run manually:
   ```bash
   # when you're ready to cut <version>:
   git tag -a <version> -m "<version>"
   git push origin <version>
   gh release create <version> --notes-file notes.md   # or create it in the GitHub UI
   ```
   Mark these clearly as **the user's to run** — the skill runs none of them.

**Never** publish a release, push a tag, or promote to latest. In CI/non-interactive
mode, default to print-only (path 2) — draft nothing without an explicit opt-in.

## Report format

```
## Release draft — <version>

Notes source: CHANGELOG.md [<version>]  |  commit delta <prior>..HEAD (no changelog)
Prior tag:     <prior>          Target:  <branch/sha>
Body:          <shown above / written to scratchpad/notes.md>

Action:  draft release created → <url>     (gh present + opted in)
   -or-  printed — no release drafted, no tag pushed
Reminder: publishing the draft (and pushing the tag) is your action, not this skill's.
```

## Safety rails

- **Draft only.** Never publish a release, never push a tag, never promote to latest
  (§A3). No `--no-verify`; never bypass a gate.
- **Compose with `/changelog`** — reuse its section as the body; don't re-summarize when
  a changelog exists. Point at `/changelog` when the changelog is missing/stale.
- **Ground the body in real changes** (§A6) — no invented release highlights.
- **Don't guess a version** — take it or infer it transparently, and confirm.
- **`gh` detected, never required** (§A5); the print-and-run fallback always works.
- Keep the notes draft out of the repo tree (scratchpad/temp only).
