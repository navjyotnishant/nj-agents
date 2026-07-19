---
name: pre-push-review
description: Use this skill when the user asks to "review my changes before I push", "run the pre-push review", "check this diff before committing/pushing", "do a thorough review of the current changes", or wants an AI-assisted quality gate over the current commit or uncommitted work. Runs four review dimensions (correctness, secrets, tests/build, style) — the secret scan first as a gate, then the other three in parallel — and aggregates one PASS / WARN / BLOCK verdict. Works in any git repo; nothing here is specific to one project, stack, or tool.
version: 0.1.0
---

# Pre-Push Review (umbrella)

A thorough, AI-assisted review of the **current commit or uncommitted changes**
before they are pushed — or any time it is triggered manually. It orchestrates
four dedicated review dimensions:

- **secrets** — leaked credentials/keys/tokens, injection, authz, unsafe patterns
- **correctness** — logic bugs, regressions, edge cases, missing validation
- **tests/build** — auto-detected test/lint/build commands, run as a gate
- **style** — conventions, commit-message hygiene, leftover debug/TODO output

This is a **procedure, not a fixed script**. Every repo has a different stack,
branch layout, and tooling — discover them each run rather than assuming a prior
repo's answers apply. It **advises only**: it never pushes, commits, or bypasses
git hooks, and leaves no files in the repo.

## Step 0 — Print the warning banner FIRST

Before running any git command or reading any diff, print this banner verbatim:

```
╔══════════════════════════════════════════════════════════════════╗
║  PRE-PUSH REVIEW — AI-ASSISTED                                    ║
╠══════════════════════════════════════════════════════════════════╣
║  This generates a SNAPSHOT of your changes (git diff of staged,   ║
║  unstaged, and committed-but-unpushed work) and shares it with    ║
║  AI (this Claude session + its subagents) for review. No external ║
║  API is called — the current session does the analysis.           ║
║                                                                   ║
║  BEFORE any snapshot is shared, a local secret scan runs. If a    ║
║  credential/key/token is detected, the review STOPS and shares    ║
║  nothing until you remove it.                                     ║
║                                                                   ║
║  This tool ADVISES only. It never pushes, commits, bypasses git   ║
║  hooks, or leaves files in your repo.                             ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository.** If `git rev-parse --git-dir` fails, stop and say so.
- **A diff to review.** If staged + unstaged + unpushed is all empty, report
  "nothing to review" and exit cleanly.
- **No external API key.** This uses the current Claude session — never ask for
  or require `ANTHROPIC_API_KEY` or any credential.
- **Optional, auto-detected:** a test / lint / build command. Discovered per
  repo by the tests/build dimension; absence is reported, not fatal.
- **Optional:** a configured upstream (`@{upstream}`). If missing, the
  unpushed-commits scope falls back to a diff against the default branch.

## Step 1 — Check prerequisites

```bash
git rev-parse --git-dir >/dev/null 2>&1 || { echo "Not a git repository."; exit 0; }
```

Determine whether there is anything to review (see Step 2's scope). If the
combined diff is empty, print "Nothing to review — working tree and unpushed
history are clean." and stop.

## Step 2 — Build the snapshot (local, NOT yet shared)

Assemble the reviewable delta using plain git only — no stack assumptions.
Default scope is everything not yet on the remote:

```bash
git diff --cached                 # staged
git diff                          # unstaged
# unpushed commits — prefer upstream, fall back gracefully:
UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null)
if [ -n "$UPSTREAM" ]; then RANGE="$UPSTREAM..HEAD"; else
  DEFAULT=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
  RANGE="${DEFAULT:-HEAD}..HEAD"
fi
git diff "$RANGE"                 # committed-but-unpushed
git log "$RANGE" --format='%h %s' # unpushed commit messages (for style/commit hygiene)
```

Also capture a file list: `git diff --name-status` (and `--cached`, and over the
range). Keep all of this **in memory / a scratchpad temp file only** — do NOT
write anything into the repo, and do NOT hand it to any subagent yet.

## Step 3 — Secret-scan GATE (inline, local, before anything is shared)

Run the `review-secrets` local scan over the **added lines** of the snapshot
(regex for common credential shapes + high-entropy strings). This is a hard
gate:

- **If a likely secret is found → STOP.** Print the file:line and the matched
  pattern (mask the actual value). Do **not** spawn any agent. Do **not** share
  the snapshot with anything. Tell the user to remove/rotate the secret (or
  confirm a false positive) and re-run. The review does not continue.
- **If clean →** the snapshot is cleared for review; proceed to Step 4.

This ordering is non-negotiable: handing the diff to any subagent counts as
"sharing with AI," so secrets must clear first.

## Step 4 — Spawn the other three dimensions in parallel

Once the snapshot is cleared, spawn **three agents in a single message**
(parallel), each receiving the cleared snapshot in its prompt:

- `correctness-reviewer` — bugs/regressions/edge cases/missing validation
- `tests-build-runner` — auto-detect and run test/lint/build; report pass/fail
- `style-reviewer` — conventions, commit-message hygiene, leftover debug/TODO

(Secrets was already handled inline in Step 3 — it is not re-spawned here.)

Each agent returns a structured report: findings rated 0–100 confidence
(report only ≥80), tagged `BLOCKER` / `WARNING` / `NIT` with file:line and a
one-line fix, plus a dimension verdict `PASS` / `WARN` / `BLOCK` (tests/build
may also return `SKIP` if no command is detected).

## Step 5 — Aggregate and report

Combine the secret-scan result + three agent reports into one verdict:

- **BLOCK** — a secret was found, or any dimension returned BLOCK (real bug,
  failing tests, etc.).
- **WARN** — only WARNINGs / NITs across dimensions.
- **PASS** — all clean.

Print a compact table, then the recommendation:

```
Dimension      Verdict   Top findings
────────────   ───────   ────────────────────────────────────
Secrets        PASS      —
Correctness    BLOCK     off-by-one in pager (src/list.js:42)
Tests / Build  PASS      npm test: 128 passed
Style          WARN      leftover console.log (src/api.js:88)
────────────   ───────
OVERALL: BLOCK — fix the correctness blocker before pushing.
```

This tool **advises only** — it never pushes. Blocking an actual `git push`
only happens if the user has wired the optional hook (below).

## Step 6 — Optional: offer to gate on git push (propose, never silently add)

If the repo has no push-gate wired and the user is interested, *offer* one of
these — and only install with explicit, per-project confirmation. Never touch
global config, never bypass with `--no-verify`.

**Option A — native `.git/hooks/pre-push`** (gates any push by anyone; per-clone,
not committed). Best for team-wide gating:

```sh
#!/bin/sh
# nj-agents pre-push gate — runs the review, blocks push on BLOCK.
# Bypass is possible with `git push --no-verify` (a conscious, visible choice).
# (Invoke your review runner here and exit non-zero on BLOCK.)
```

**Option B — project `.claude/settings.json` `PreToolUse` hook** matching
`Bash(git push*)` (gates pushes made *through Claude*). Best for solo-Claude
workflows.

Recommend A for team gating, B for solo-Claude. Present the snippet; write it
only on the user's go-ahead.

## Step 7 — Clean up

- Remove any scratch/temp files created for the snapshot — nothing stays in the
  repo tree (use the scratchpad/temp dir, never the project).
- Never leave a hook, config change, or scaffold behind unless the user asked
  for it in Step 6.
- Summarize: overall verdict, the top findings per dimension, and anything
  skipped (e.g. tests/build SKIP when no command was found) that the user should
  check manually.

## Running a single dimension

Each dimension is also a standalone skill — `/review-secrets`,
`/review-correctness`, `/review-tests-build`, `/review-style` — for when you
only want one. They each print the banner, run their own prereq + snapshot
steps, and (except secrets, which scans locally first) spawn their matching
agent.
