---
name: review-style
description: Use this skill when the user asks to "review my changes for style", "check conventions before I push", "review my commit messages", or wants a consistency/hygiene review of the current commit or uncommitted work. Checks the diff against surrounding code conventions, commit-message hygiene, and leftover debug/TODO/console output. Works in any git repo; nothing here is project-specific.
version: 0.1.0
---

# Review: Style & Conventions

Consistency and hygiene review of the **current commit or uncommitted changes** —
does the new code read like the code around it, are commit messages clean, and is
there leftover debug output. It infers conventions from the **surrounding code**,
not from a hardcoded style guide, so it works in any repo.

## Step 0 — Print the warning banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  STYLE & CONVENTIONS REVIEW — AI-ASSISTED                        ║
╠══════════════════════════════════════════════════════════════════╣
║  This shares a SNAPSHOT of your diff (and unpushed commit         ║
║  messages) with AI (this Claude session + subagent) to review     ║
║  style and hygiene. No external API is called. A local secret     ║
║  scan runs before sharing. This tool ADVISES only.                ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop.
- **A diff to review** (staged + unstaged + unpushed); if empty, report and exit.
- **No external API key** — uses the current Claude session.

## Step 1 — Build the snapshot (local, NOT yet shared)

Same scope as the umbrella: `git diff --cached` + `git diff` + the unpushed range,
**plus the unpushed commit messages** (`git log <range> --format='%h %s%n%b'`) for
the commit-hygiene check. Keep it in memory / scratchpad only; never write to the
repo.

## Step 2 — Secret-scan gate before sharing

Before handing the diff to the agent, run the local secret scan from
`review-secrets`. If a likely secret is found, **hard stop** — share nothing and
tell the user to resolve it first. Only a clean scan proceeds.

## Step 3 — Spawn the style agent

Spawn `style-reviewer` with the cleared snapshot. It checks:

- **Consistency with surrounding code** — naming, formatting, idioms, error
  handling, and comment density that match the neighbouring lines (inferred from
  the diff context, not an external style guide).
- **Commit-message hygiene** — imperative mood, meaningful subject, no "wip"/"fix
  stuff"/"asdf", reasonable scope per commit, matches any convention the other
  unpushed messages already follow (e.g. Conventional Commits if in use).
- **Leftover artifacts** — `console.log` / `print` / `dbg!` debug output, `TODO`/
  `FIXME`/`XXX` added in the diff, commented-out code blocks, stray focus flags in
  tests (`.only`, `fdescribe`), and merge-conflict markers.

## Step 4 — Report

Print the agent's findings (confidence ≥80 only), each tagged `WARNING` / `NIT`
with file:line and a fix. Style issues are rarely BLOCKERs — dimension verdict is
usually **WARN** or **PASS**; reserve BLOCK for things that shouldn't ship (a
committed merge-conflict marker, a `.only` that disables the test suite). Advises
only — never pushes. Clean up any scratch files.
