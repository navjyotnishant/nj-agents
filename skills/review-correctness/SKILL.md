---
name: review-correctness
description: Use this skill when the user asks to "review my changes for bugs", "check this diff for correctness", "did I introduce a regression", or wants a correctness-focused review of the current commit or uncommitted work before pushing. Reviews the changed lines and their blast radius for logic errors, regressions, unhandled edge cases, and missing validation. Works in any git repo; nothing here is project-specific.
version: 0.2.0
---

# Review: Correctness & Bugs

Correctness-focused review of the **current commit or uncommitted changes** — logic
errors, regressions, unhandled edge cases, and missing validation introduced by the
diff. Scope is the **changed lines and their blast radius** (callers of changed
code, changed contracts), not the whole repo.

Follow the shared rules in `CONVENTIONS.md` (snapshot scope §1, diff hygiene §2,
secret gate §3, findings format §4, CI mode §5, report §6, safety §7).

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
