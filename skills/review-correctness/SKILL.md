---
name: review-correctness
description: Use this skill when the user asks to "review my changes for bugs", "check this diff for correctness", "did I introduce a regression", or wants a correctness-focused review of the current commit or uncommitted work before pushing. Reviews the changed lines and their blast radius for logic errors, regressions, unhandled edge cases, and missing validation. Works in any git repo; nothing here is project-specific.
version: 0.3.0
class: review
subclass: gate
---

# Review: Correctness & Bugs

Correctness-focused review of the **current commit or uncommitted changes** — logic
errors, regressions, unhandled edge cases, and missing validation introduced by the
diff. Scope is the **changed lines and their blast radius** (callers of changed
code, changed contracts), not the whole repo.

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
║  CORRECTNESS REVIEW — AI-ASSISTED                                ║
╠══════════════════════════════════════════════════════════════════╣
║  This shares a SNAPSHOT of your diff with AI (this Claude session ║
║  + subagent) to review it for bugs. No external API is called;    ║
║  nothing leaves this machine. A secret scan runs before the       ║
║  snapshot is shared. This tool ADVISES only.                      ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **A diff to review** (staged + unstaged + unpushed); if empty, report and stop.
- **No external API key** — uses the current Claude session.

## Step 1 — Snapshot + hygiene + secret gate

Build the snapshot (`CONVENTIONS.md §1`), apply diff hygiene (§2), then run the
secret-scan gate (§3 / `review-secrets`) **before sharing anything**. A credible
secret hit is a hard stop — share nothing, tell the user (interactive) or BLOCK with
exit 1 (CI). Only a clean scan proceeds.

## Step 2 — Spawn the correctness agent

**Cost check first (`CONVENTIONS.md §8`).** One agent is cheap, but a trivial diff
does not need one: for a change under ~20 lines across one or two files, review it
inline and say so rather than spawning. For anything larger, state the scope in one
line — `Reviewing 12 files / 340 lines with 1 correctness agent.` — and proceed.
Never re-run more than twice on the same change without being asked.

Spawn `correctness-reviewer` with the cleared, hygiene-filtered snapshot. It traces
each hunk for: off-by-one/boundary errors, null/undefined/None dereferences,
inverted or wrong conditionals, changed signatures/return contracts that break
existing callers, unhandled error/edge cases, missing validation on new inputs,
resource leaks, and concurrency hazards in changed code.

## Step 3 — Report

Per `CONVENTIONS.md §4`: findings ≥80 confidence, tagged `BLOCKER`/`WARNING`/`NIT`
with `file:line` and a concrete fix, plus a dimension verdict — **BLOCK** for a real
bug, **WARN** for risky-but-not-broken, **PASS** if clean. Write the report artifact
(§6) if run standalone. Advises only; clean up scratch files.
