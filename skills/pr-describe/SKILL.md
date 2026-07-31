---
name: pr-describe
description: Use this skill when the user asks to "describe this PR", "write the PR description", "draft a pull request", "summarize this branch for a PR", or wants a clear PR title and body for the current branch. Reads the branch's whole delta versus its base (the PR view) plus its commit messages, and drafts a structured title + body (summary, what changed, why, test plan, related issues). Opens a DRAFT PR only if the user opts in and `gh` is present — otherwise it hands you the text. Never pushes, never opens a non-draft PR on its own. Works in any git repo; nothing here is project-specific.
version: 0.1.0
class: workflow
author: navjyotnishant
---

# PR Describe (workflow)

Drafts a **pull-request title and body** for the current branch, grounded in the
branch's actual commits and diff versus its base. It produces text you paste, or —
if you opt in and `gh` is available — a **draft** PR you then review and publish.

This is a **workflow-class** skill. It sits between the two existing classes and
borrows the safe halves of each:

- Like the **review class**, it reads a diff and invents nothing — every line of the
  description traces to a real commit or code change (`CONVENTIONS.md §1` snapshot
  scope, `CONVENTIONS-authoring.md §A6` grounding).
- Like the **authoring class**, it **proposes and never auto-acts**
  (`CONVENTIONS-authoring.md §A3`): it never `git push`es, never opens a
  non-draft PR, never merges. `gh` is **detected, never required** (§A5).

> **Finding the conventions file.** It lives at the toolkit repo root, two levels
> above this skill — not beside `SKILL.md`. Skills are usually installed as
> symlinks into your runner's skills directory, so a plain relative path resolves against the
> *link* and misses it. Resolve the link first:
>
> ```bash
> ROOT="$(dirname "$(readlink -f "<this skill's base directory>")")/.."
> ```
>
> then read `$ROOT/CONVENTIONS-authoring.md` and `$ROOT/CONVENTIONS.md`. If a file is genuinely absent, say so and continue
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

**It does not write a file into the repo tree.** The artifact is a PR, so the
authoring placement rules (§A2/§A4) don't apply — the output goes to GitHub (as a
draft) or to your clipboard, never to `docs/`. Say so rather than forcing a file.


## Dependencies

Detected at runtime, never installed by this skill (`§A5`).

| Tool | Used for | Without it |
|---|---|---|
| `gh` | opening a draft PR on opt-in | prints the title and body for you to paste |

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  PR-DESCRIBE — WORKFLOW                                           ║
╠══════════════════════════════════════════════════════════════════╣
║  Drafts a PR title + body from this branch's commits and diff.    ║
║  Grounded in the real delta — nothing invented. It PROPOSES:      ║
║  it never pushes, never opens a non-draft PR, never merges.       ║
║  A draft PR is created only if you opt in and `gh` is present.    ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **A branch with a delta versus its base.** If the branch equals its base (no
  commits ahead), report "nothing to describe — this branch matches <base>" and stop.
- **No API key / no network for the drafting itself.** `gh` (GitHub CLI) is used
  **only if present and only if you opt in**, to create a draft PR (§A5). Absent or
  declined → the skill prints the title + body for you to paste.

## Step 1 — Resolve the base and the PR delta

The "PR view" is the branch versus the base it will merge into — its whole delta,
not just unpushed commits. Resolve deterministically (plain git, no stack
assumptions), consistent with `CONVENTIONS.md §1`:

```bash
# base branch: explicit arg > the PR's target > origin's default HEAD > main
BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
BASE="${BASE:-main}"
CUR=$(git rev-parse --abbrev-ref HEAD)
MB=$(git merge-base "origin/$BASE" HEAD 2>/dev/null || git merge-base "$BASE" HEAD)

git log  "$MB..HEAD" --no-merges --format='%H%x09%s%x09%b'   # commits in the PR
git diff "$MB..HEAD" --stat                                   # files touched
git diff "$MB..HEAD"                                          # full delta
```

- If the user names a base ("against `develop`", "compare to `release/2.0`"), honor it.
- If `HEAD` **is** the default branch (no feature branch), say so and ask which base
  to compare against — do not invent one.
- Keep the collected diff **in memory or the scratchpad only**, never in the repo tree.

## Step 2 — Ingest light repo context (§A1)

Just enough to describe accurately and match the repo's conventions:

- Project name/purpose, and the **PR-body style the repo already uses** — read a few
  recent merged PRs via `gh pr list --state merged` **if `gh` is present** (§A5), or
  an existing `.github/PULL_REQUEST_TEMPLATE.md`. Match that shape when it exists;
  don't impose this skill's default template over a repo's own.
- Whether commits are **Conventional Commits** (drives the title prefix).

## Step 3 — Detect a PR template and issue links

- **`.github/PULL_REQUEST_TEMPLATE.md`** (or `docs/`/root variants): if present, fill
  **that** template from the delta rather than the default body below. Leave a
  template's checklist items unchecked — the human ticks those.
- **Linked issues:** scan the branch name and commit messages for issue keys
  (`#123`, `NAV-52`, `PROJ-45`). List them as candidates; use the repo's closing-keyword
  convention (`Closes #123`) only when the change actually resolves the issue — never
  assert a close you can't support (§A6).

## Step 4 — Spawn the pr-describer agent

Spawn `pr-describer` with the branch delta from Step 1 (commits + diff), the repo
context from Step 2, and any PR template / issue links from Step 3. It returns the
title and body — de-duplicating commit noise, grouping bullets by concern rather
than one-per-commit, and grounding every line in a real commit or hunk.

The shape it returns, and the rules it works to:

**Title** — one line, imperative, matching repo convention. If the repo uses
Conventional Commits, prefix accordingly (`feat:`, `fix:`, …) inferred from the
commits; a single-commit branch can reuse its subject.

**Body** — the default template when the repo has none. Include only sections the
delta supports; drop empty ones rather than emitting `N/A` filler:

```markdown
## Summary
<1–3 sentences: what this PR does and why, in user/reviewer terms>

## Changes
- <grouped, de-duplicated bullets — by area or concern, not one-per-commit>

## Why
<the motivation / problem being solved, when not obvious from Summary>

## Test plan
- <how it was or should be verified — grounded in tests actually present
  in the diff, or the commands a reviewer would run; never fabricate results>

## Related
Closes #<n>   ·   Refs #<n>
```

**Grounding rules (§A6):**
- Every bullet traces to a real commit or diff hunk. No invented features, no
  "improved performance" without a change that supports it.
- The **test plan describes verification, it does not claim passing results** unless
  the diff shows tests and the user ran them. If unsure, phrase as "to verify: …".
- Collapse noise (`wip`, `fixup!`, `merge`, format-only commits) — describe the net
  change, not the commit-by-commit history.

## Step 5 — Present, then offer the draft PR (opt-in)

Show the title and body in full for review. Then resolve the action by capability
(§A5), always defaulting to the safe path:

1. **`gh` present, on a GitHub remote, and the user opts in** → create a **draft**:
   ```bash
   gh pr create --draft --base "$BASE" --title "<title>" --body-file <scratchpad/body.md>
   ```
   A draft, always — never `--web` auto-submit, never a ready PR. Report the URL and
   that it's a **draft** the user opens/marks-ready themselves. If the branch isn't
   pushed, `gh` will say so; surface that rather than pushing it for them (pushing is
   the user's call, §A3).
2. **`gh` absent, not GitHub, or the user declines** → print the title and the body
   (and write the body to the scratchpad so it's easy to copy). Note that no PR was
   created and nothing was pushed.

**Never** push the branch, open a non-draft PR, or merge. In non-interactive/CI mode,
default to path 2 (print only) — do not create anything without an explicit opt-in.

## Report format

```
## PR draft — <branch> → <base>

Scope:   <N commits, M files> (merge-base <base>..HEAD)
Grounded in: commits + diff (+ recent merged PRs for style, if gh present)

Title:   <the title>
Body:    <shown above / written to scratchpad/body.md>

Action:  draft PR created → <url>        (gh present + opted in)
   -or-  printed for paste — no PR created, nothing pushed
Related: <issue keys found, and which are proposed as "Closes">
```

## Safety rails

- **Never push, never open a non-draft PR, never merge** (§A3). No `--no-verify`.
- **Ground everything** — every claim traces to a commit or diff hunk (§A6). No
  invented changes; no test *results* unless actually run.
- **Respect the repo's own PR template** over this skill's default when one exists.
- **`gh` detected, never required** (§A5); the print-and-paste path always works.
- Keep the diff snapshot out of the repo tree (scratchpad/temp only).
