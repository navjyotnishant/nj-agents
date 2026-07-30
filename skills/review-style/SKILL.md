---
name: review-style
description: Use this skill when the user asks to "review my changes for style", "check conventions before I push", "review my commit messages", or wants a consistency/hygiene review of the current commit or uncommitted work. Checks the diff against surrounding code conventions, commit-message hygiene, and leftover debug/TODO/console output. Works in any git repo; nothing here is project-specific.
version: 0.3.0
class: review
subclass: gate
---

# Review: Style & Conventions

Consistency and hygiene review of the **current commit or uncommitted changes** —
does the new code read like the code around it, are commit messages clean, and is
there leftover debug output. Conventions are inferred from the **surrounding code**,
not a hardcoded style guide, so it works in any repo.

Follow the shared rules in `CONVENTIONS.md` (snapshot scope §1, diff hygiene §2,
secret gate §3, findings format §4, CI mode §5, report §6, safety §7).

> **Finding the conventions file.** It lives at the toolkit repo root, two levels
> above this skill — not beside `SKILL.md`. Skills are usually installed as
> symlinks into `~/.claude/skills/`, so a plain relative path resolves against the
> *link* and misses it. Resolve the link first:
>
> ```bash
> ROOT="$(dirname "$(readlink -f "<this skill's base directory>")")/.."
> ```
>
> then read `$ROOT/CONVENTIONS.md`. If a file is genuinely absent, say so and continue
> with the procedure below rather than stopping.

> **Spawning subagents — `CONVENTIONS-orchestration.md`.** This skill spawns agents,
> so `§C` (cost) and `§R` (progress reporting) apply. **Cost shape:** 1–2 agent calls.
> State it and get a yes before the first dispatch; cap fix rounds at 2; halt on any
> signal to stop. Announce the **pipeline** up front and each stage as it starts, so a stall is
> attributable to a named stage (`§R`).

## Step 0 — Print the warning banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  STYLE & CONVENTIONS REVIEW — AI-ASSISTED                        ║
╠══════════════════════════════════════════════════════════════════╣
║  This shares a SNAPSHOT of your diff (and unpushed commit         ║
║  messages) with AI (this Claude session + subagent) to review     ║
║  style and hygiene. No external API is called; nothing leaves     ║
║  this machine. A secret scan runs before sharing. ADVISES only.   ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **A diff to review** (staged + unstaged + unpushed); if empty, report and stop.
- **No external API key** — uses the current Claude session.

## Step 1 — Snapshot + hygiene + secret gate

Build the snapshot (`CONVENTIONS.md §1`), including the **unpushed commit messages**
for the commit-hygiene check. Apply diff hygiene (§2), then run the secret-scan gate
(§3) before sharing anything — a credible hit is a hard stop. Only a clean scan
proceeds.

## Step 2 — Spawn the style agent

**Cost check first (`CONVENTIONS.md §8`).** If the repo has a formatter or linter
that already covers the diff (`gofmt`, `prettier`, `ruff`, `eslint`), run it and
report that result before spawning — a deterministic tool answers the mechanical
half for free, leaving the agent for the judgement half (naming, comment density,
leftover debug output). For a trivial diff, review inline instead. Never re-run
more than twice on the same change without being asked.

Spawn `style-reviewer` with the cleared snapshot. It checks: consistency with
surrounding code (naming, formatting, idioms, error handling, comment density, reuse
of existing helpers), commit-message hygiene (imperative mood, meaningful subject,
no `wip`/`fix`/`asdf`, matches the repo's existing convention e.g. Conventional
Commits), and leftover artifacts (`console.log`/`print`/`dbg!` debug output,
`TODO`/`FIXME`/`XXX` added in the diff, commented-out code, test-focus flags like
`.only`/`fdescribe`, and — as a hard flag — committed merge-conflict markers).

## Step 3 — Report

Per `CONVENTIONS.md §4`: findings ≥80 confidence, tagged `WARNING`/`NIT` (rarely
`BLOCKER`) with `file:line` (or commit hash) and a fix, plus a dimension verdict —
usually **WARN** or **PASS**; reserve **BLOCK** for things that shouldn't ship (a
committed conflict marker, a `.only` that disables the suite). Write the report
artifact (§6) if run standalone. Advises only; clean up scratch files.
