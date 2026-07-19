---
name: review-correctness
description: Use this skill when the user asks to "review my changes for bugs", "check this diff for correctness", "did I introduce a regression", or wants a correctness-focused review of the current commit or uncommitted work before pushing. Reviews the changed lines and their blast radius for logic errors, regressions, unhandled edge cases, and missing validation. Works in any git repo; nothing here is project-specific.
version: 0.1.0
---

# Review: Correctness & Bugs

Correctness-focused review of the **current commit or uncommitted changes** —
logic errors, regressions, unhandled edge cases, and missing validation
introduced by the diff. Scope is the **changed lines and their blast radius**
(callers of changed functions, changed contracts), not the whole repo.

## Step 0 — Print the warning banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  CORRECTNESS REVIEW — AI-ASSISTED                                ║
╠══════════════════════════════════════════════════════════════════╣
║  This shares a SNAPSHOT of your diff with AI (this Claude session ║
║  + subagent) to review it for bugs. No external API is called.    ║
║  A local secret scan runs before the snapshot is shared. This     ║
║  tool ADVISES only — it never pushes or commits.                  ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop.
- **A diff to review** (staged + unstaged + unpushed); if empty, report and exit.
- **No external API key** — uses the current Claude session.

## Step 1 — Build the snapshot (local, NOT yet shared)

Same scope as the umbrella: `git diff --cached` + `git diff` + the unpushed range
(`@{upstream}..HEAD`, falling back to the default branch, then `HEAD`). Keep it in
memory / scratchpad only; never write to the repo.

## Step 2 — Secret-scan gate before sharing

Before handing the diff to the agent, run the local secret scan from
`review-secrets` (Step 2 there). If a likely secret is found, **hard stop** —
print the masked hit, share nothing, and tell the user to resolve it first. Only
a clean scan proceeds.

## Step 3 — Spawn the correctness agent

Spawn `correctness-reviewer` with the cleared snapshot. It traces each hunk for:
off-by-one and boundary errors, null/undefined/None dereferences, incorrect
conditionals and inverted logic, changed function signatures/return contracts
that break existing callers, unhandled error/edge cases, missing validation on
newly-introduced inputs, resource leaks, and concurrency hazards in changed code.

## Step 4 — Report

Print the agent's findings (confidence ≥80 only), each tagged `BLOCKER` /
`WARNING` / `NIT` with file:line and a concrete fix, and a dimension verdict:
**BLOCK** if a real bug, **WARN** for risky-but-not-broken, **PASS** if clean.
Advises only — never pushes. Clean up any scratch files.
