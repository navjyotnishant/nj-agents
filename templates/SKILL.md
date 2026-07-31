---
name: SKILL_NAME
description: Use this skill when the user asks to "…", "…", or wants …. <One or two sentences on what it actually does.> Works in any git repo; nothing here is project-specific.
version: 0.1.0
class: SKILL_CLASS
author: AUTHOR_NAME
---

<!--
  Scaffolded by `./check.sh --new-skill`. Fill every ALL-CAPS placeholder and every
  section marked REQUIRED for your class, then run `./check.sh` — it will tell you
  what is still missing. Delete these comments before committing.

  class: review | authoring | workflow | pm | social
    review     advise only, never write a file, never commit  → CONVENTIONS.md
               ALSO add `subclass: gate` (reviews a diff, returns PASS/WARN/BLOCK)
               or `subclass: scan` (sweeps the whole repo, returns candidates)
    authoring  writes ONE artifact, then PROPOSES the commit  → CONVENTIONS-authoring.md
    workflow   reads a diff, drafts a PR/commit, never runs git
    pm         writes a work item into a tracker, proposes the create → CONVENTIONS-pm.md
    social     paste-ready copy, never writes to the repo, never posts

  RUNNER-NEUTRAL, and check.sh enforces it. This toolkit installs into Claude Code,
  Codex, Cursor and Gemini from one clone, so a skill must not assume which one is
  reading it:

    - Say "this session", never "this <vendor> session". The privacy claim stays
      true either way; naming a vendor makes it false on three runners out of four.
    - Never recommend a model ("run this on haiku"). The session picks the model.
    - Name a runner only when the difference is the point — "Option B is Claude
      Code only" is correct and useful; "shares your diff with Claude" is not.
    - `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` are fine to READ as repo input. They
      are real files in real repos, whatever tool you run.
-->

# SKILL TITLE

<One paragraph: what this skill does, what it produces, and what it will never do.
The "never" half matters — it is the promise the class contract enforces.>

This is a **SKILL_CLASS-class** skill — follow `CONVENTIONS_DOC` (…list the sections
you actually rely on…).

> **Finding the conventions file.** It lives at the toolkit repo root, two levels
> above this skill — not beside `SKILL.md`. Skills are usually installed as
> symlinks into `~/.claude/skills/`, so a plain relative path resolves against the
> *link* and misses it. Resolve the link first:
>
> ```bash
> ROOT="$(dirname "$(readlink -f "<this skill's base directory>")")/.."
> ```
>
> then read `$ROOT/CONVENTIONS_DOC`. If a file is genuinely absent, say so and continue
> with the procedure below rather than stopping.

<!--
  REQUIRED IF THIS SKILL SPAWNS AGENTS. Uncomment the block below and replace
  COST_SHAPE with the real fleet — "4 agent calls", "a render → QA → fix loop,
  usually 2–4 calls". It stays commented out until you do, so check.sh reports the
  skill as missing its cost and progress rules rather than passing on placeholder
  text. Delete the whole thing if this skill spawns nothing.

> **Spawning subagents — `CONVENTIONS-orchestration.md`.** This skill spawns agents,
> so `§C` (cost) and `§R` (progress reporting) apply. **Cost shape:** COST_SHAPE.
> State it and get a yes before the first dispatch; cap fix rounds at 2; halt on any
> signal to stop. Announce the **roster** before dispatch — every agent and what it
> will do — then mark each one `✓`/`✗` with its verdict as it lands (`§R`).
-->

<!--
  If this skill does NOT spawn agents, delete both blocks above and make sure the
  word "spawn" never appears in the body — check.sh keys off it.
-->



## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  SKILL NAME — CLASS                                              ║
╠══════════════════════════════════════════════════════════════════╣
║  <What it does, in one or two lines.>                            ║
║  <What it will NOT do — the safety promise.>                     ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- <Any tool this skill uses — DETECTED at runtime, never required (§A5). State the
  zero-dependency fallback for each.>

## Step 1 — <Ingest / resolve scope>

<Ground the work in the actual repo. Never invent an API, path, version, or claim.>

## Step 2 — <Do the thing>

<!--
  REQUIRED BY CLASS — check.sh enforces these:

  review    Reference NJ_AGENTS_CI (or CONVENTIONS.md §5) for CI mode. A `gate` must
            define its BLOCK verdict; a `scan` reports candidates instead.
  authoring Cite §A3 (show git status/diff, print the commit block, NEVER run git)
            and §A4 (name exactly where the artifact lands).
  pm        Cite §P2 (neutral issue model) and carry a paste-ready-markdown fallback
            for when no tracker MCP is connected.
  workflow  State plainly that this skill never runs git.
-->

## Step 3 — Report

<What the user sees at the end. Be concrete: a verdict, a path, a diff, a command.>

## Safety rails

- <The things this skill must never do. Restate the class promise in its own terms.>
- **Degrade, don't fail** — every external tool is detected at runtime with a
  documented fallback (§A5).
- **Ground everything in the actual repo** — no invented APIs, paths, or results.
