---
name: capture-intent
description: Use this skill when the user asks to "capture this idea", "write down the intent behind this", "save this as an intent doc before we plan it", or has a raw idea to record as-is before any formal planning starts. Writes docs/intent/<slug>.md with a fixed shape (Intent / Why now / Rough shape / Captured+Author) and proposes the commit. Works in any git repo; nothing here is project-specific.
version: 0.1.0
class: workflow
author: navjyotnishant
---

# Capture Intent (workflow)

Captures a raw idea, in the user's own words, as **one committed file** —
`docs/intent/<slug>.md` — before it's shaped into a Story or Epic. This is the seed
`/pm-plan` and `/pm-story` can point at as grounding context, and the record of *why*
a piece of work started that a tracker item alone doesn't carry.

This is a **workflow-class** skill: it reads the conversation like a diff (nothing to
diff against yet, but the same discipline — record only what was actually said) and
drafts one artifact, proposing the commit per `CONVENTIONS-authoring.md` **§A3**
(show the diff, print the exact `git add`/`git commit` block, never run git) and
**§A4** (the artifact lands at a fixed, named path — never invented). It never runs
git itself.

> **Finding the conventions file.** It lives at the toolkit repo root, two levels
> above this skill — not beside `SKILL.md`. Skills are usually installed as
> symlinks into your runner's skills directory, so a plain relative path resolves
> against the *link* and misses it. Resolve the link first:
>
> ```bash
> ROOT="$(dirname "$(readlink -f "<this skill's base directory>")")/.."
> ```
>
> then read `$ROOT/CONVENTIONS-authoring.md`. If it's genuinely absent, say so and
> continue with the procedure below rather than stopping.

> **Every skill follows `CONVENTIONS-orchestration.md` §U** — ground everything in
> the actual repo, never run git on your own initiative, no secrets in output,
> keep `CHANGELOG.md` current when the change is user-facing, degrade rather than
> fail, and say what you did not do.

This is a single-turn draft-and-propose, done entirely by the current session —
no subagent, no external tool, no network.

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  CAPTURE-INTENT — WORKFLOW                                        ║
╠══════════════════════════════════════════════════════════════════╣
║  Writes docs/intent/<slug>.md from the idea as you've described    ║
║  it — nothing invented, nothing filled in. Proposes the commit;   ║
║  never runs git.                                                   ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- Nothing else. No external tool, no MCP, no network — the draft comes entirely
  from what's already been said in conversation.

## Step 1 — Pull the idea from conversation, don't ask a fresh interview

Use what the user has already said as the source. If the conversation genuinely
doesn't contain enough to fill a section, leave it out or mark it rather than
inventing detail to complete the shape (`CONVENTIONS-authoring.md` §A6) — a thin
intent file is more honest than a padded one.

Derive a short kebab-case `<slug>` from the idea's subject (e.g. "cache warm start"
→ `cache-warm-start`). If `docs/intent/<slug>.md` already exists, say so and ask
whether to append a dated addendum or pick a different slug — never silently
overwrite a prior capture.

## Step 2 — Draft the file

Fixed shape, in this order:

```markdown
# <Idea, as a short title>

## Intent

<The idea itself, in the user's own words — paraphrased for clarity, not
reinterpreted. What is being proposed and what it's for.>

## Why now

<The trigger — what prompted this idea today rather than some other time. If the
user didn't say, write "not stated" rather than guessing at a motivation.>

## Rough shape

<Optional. Only include this section if the user sketched some approach or shape
for the idea. Mark it explicitly:>

> **Unrefined** — a first sketch, not a plan. <the sketch>

---

Captured: <today's date, ISO format>
Author: <from `git config user.name`, or ask if unset — same convention as the
repo's standing author-header rule>
```

Omit "Rough shape" entirely rather than leaving it as an empty stub when nothing
was said about approach.

## Step 3 — Propose the commit (§A3), never run git

```bash
git status --short                    # confirm nothing else is accidentally swept in
git add docs/intent/<slug>.md
git commit -m "docs(intent): capture <short subject>"
```

Print the exact block above with the real slug and message filled in. Show the
drafted file content before the commit block so the user can review it. **Never run
`git add`, `git commit`, or `git push` on your own initiative** — print the commands
and stop. Only an explicit, separate go-ahead from the user ("commit that", "go
ahead and commit") authorizes running `git add`/`git commit`; this skill never pushes,
under any instruction, since a push is outside its scope entirely.

## Step 4 — Report

State the file path, the one-line subject, and that the commit is proposed, not
run. Mention that `/pm-plan` or `/pm-story` can later be pointed at this file as
grounding context for the same piece of work.

## Safety rails

- **Never invents scope.** Records only what was actually said; anything uncertain
  is marked, not filled in (§A6).
- **Proposes the commit, never runs git** (§A3) — the human decides what gets
  committed, always.
- **Fixed placement, no exceptions** — always `docs/intent/<slug>.md` (§A4); never
  a different directory, never inline in an existing doc.
- **Never overwrites an existing capture silently** — a slug collision is surfaced,
  not resolved by clobbering.
- **Degrade, don't fail** — no external tool is required; if `git config user.name`
  is unset, ask rather than guessing at authorship.
