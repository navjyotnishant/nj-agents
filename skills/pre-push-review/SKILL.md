---
name: pre-push-review
description: Use this skill when the user asks to "review my changes before I push", "run the pre-push review", "check this diff before committing/pushing", "do a thorough review of the current changes", or wants an AI-assisted quality gate over the current commit or uncommitted work. Runs five review dimensions (secrets, correctness, tests/build, dependencies, style) — the secret scan first as a gate, then the rest in parallel — and aggregates one PASS / WARN / BLOCK verdict with a report artifact. Supports a non-interactive CI mode with an exit-code contract. Works in any git repo; nothing here is specific to one project, stack, or tool.
version: 0.3.0
---

# Pre-Push Review (umbrella)

A thorough, AI-assisted review of the **current commit or uncommitted changes**
before they are pushed — or any time it is triggered manually or from CI. It
orchestrates five dedicated review dimensions:

- **secrets** — leaked credentials (scanner-first), plus semantic security
- **correctness** — logic bugs, regressions, edge cases, missing validation
- **tests/build** — auto-detected test/lint/build commands, run as a gate
- **dependencies** — added packages, version/license changes, supply-chain signals
- **style** — conventions, commit-message hygiene, leftover debug/TODO output

This is a **procedure, not a fixed script** — discover each repo's stack, branch
layout, and tooling at runtime. It **advises only**: it never pushes, commits, or
bypasses git hooks, and leaves no files in the repo. All shared behavior
(snapshot scope, diff hygiene, findings format, CI mode, report artifact, safety)
is defined once in **`CONVENTIONS.md`** — read it; the steps below reference it.

## Step 0 — Print the warning banner FIRST

Before running any git command or reading any diff, print this banner verbatim:

```
╔══════════════════════════════════════════════════════════════════╗
║  PRE-PUSH REVIEW — AI-ASSISTED                                    ║
╠══════════════════════════════════════════════════════════════════╣
║  This generates a SNAPSHOT of your changes (git diff of staged,   ║
║  unstaged, and committed-but-unpushed work) and shares it with    ║
║  AI (this Claude session + its subagents) for review. No external ║
║  API is called and nothing leaves this machine — the current      ║
║  session does the analysis.                                       ║
║                                                                   ║
║  BEFORE any snapshot is shared, a REQUIRED secret scanner         ║
║  (gitleaks / trufflehog / detect-secrets) runs. If none is        ║
║  installed the review BLOCKs with install steps. If a             ║
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
  "nothing to review" and stop.
- **No external API key / no network.** Uses the current Claude session; never asks
  for or requires any credential.
- **REQUIRED:** a dedicated secret scanner on PATH (`gitleaks` / `trufflehog` /
  `detect-secrets` — any one). If none is installed, the review BLOCKs with install
  instructions; there is no heuristic-only fallback gate.
- **Optional, auto-detected:** a test/lint/build command (tests/build dimension).
- **Optional:** a configured upstream (`@{upstream}`); else the unpushed scope falls
  back to the default branch (`CONVENTIONS.md §1`).

## Step 1 — Determine mode and check prerequisites

Detect interactive vs. non-interactive/CI mode per `CONVENTIONS.md §5`
(`NJ_AGENTS_CI=1`, a `--ci` arg, or the user saying it's for a pipeline/hook). In CI
mode, never prompt; resolve ambiguity to the safe (BLOCK) outcome and honor the
exit-code contract.

```bash
git rev-parse --git-dir >/dev/null 2>&1 || echo "Not a git repository."
```

If not a git repo, or the combined diff is empty, report and stop (do not proceed).

## Step 2 — Build the snapshot and apply diff hygiene

Assemble the snapshot per `CONVENTIONS.md §1`, then apply diff hygiene per §2:
exclude lockfiles/binaries/generated/vendored files from the *semantic* review
(they're still secret-scanned), and if the reviewable diff is very large, plan a
partial top-N review and say so. Keep everything in the scratchpad/temp dir — never
write into the repo. Do **not** hand anything to a subagent yet.

## Step 3 — Secret-scan GATE (inline, first, before anything is shared)

Run the `review-secrets` gate (a **required** dedicated scanner) over the added
lines, per `skills/review-secrets/SKILL.md` and `CONVENTIONS.md §3`:

- **No scanner installed → BLOCK.** Print the install instructions and stop — do
  not spawn any agent, share nothing. The overall verdict is BLOCK; a push must not
  proceed without an authoritative secret scan.
- **Any scanner hit → STOP.** Print `file:line` + rule/pattern class + **masked**
  value. Do **not** spawn any agent; share nothing. Interactive: tell the user to
  remove/rotate (or allowlist a confirmed false positive) and re-run. CI: BLOCK,
  exit 1.
- **Clean → proceed to Step 4.**

Non-negotiable ordering: handing the diff to any subagent counts as "sharing with
AI," so secrets clears first.

## Step 4 — Spawn the remaining dimensions in parallel

Once the snapshot is cleared, spawn the dimension agents **in a single message**
(parallel), each receiving the cleared, hygiene-filtered snapshot:

- `correctness-reviewer` — bugs/regressions/edge cases/missing validation
- `tests-build-runner` — auto-detect and run test/lint/build; report pass/fail
- `dependency-reviewer` — dependency/version/license changes, supply-chain signals
- `style-reviewer` — conventions, commit-message hygiene, leftover debug/TODO
- `secrets-reviewer` — the semantic security pass (secrets *gate* already ran in
  Step 3; this is the deeper injection/authz/unsafe-pattern review on the cleared
  diff)

Each returns a structured report per `CONVENTIONS.md §4` (findings ≥80 confidence,
severity-tagged, with a dimension verdict `PASS`/`WARN`/`BLOCK`/`SKIP`).

## Step 5 — Aggregate, report, and write the artifact

Aggregate per `CONVENTIONS.md §4`. Print a compact table then the recommendation:

```
Dimension       Verdict   Top findings
─────────────   ───────   ───────────────────────────────────────
Secrets         PASS      gitleaks: clean; semantic: clean
Correctness     BLOCK     off-by-one in pager (src/list.js:42)
Tests / Build   PASS      npm test: 128 passed
Dependencies    WARN      left-pad@^2 floating range (package.json:19)
Style           WARN      leftover console.log (src/api.js:88)
─────────────   ───────
OVERALL: BLOCK — fix the correctness blocker before pushing.
(scope: 12 files, 340 lines · excluded: 2 lockfiles, 1 image · scanner: gitleaks 8.x)
```

Write the **report artifact** per `CONVENTIONS.md §6` (timestamped, outside the repo
tree or under a gitignored dir, no unmasked secrets). If any dimension was `SKIP` or
the review was partial, say so beside the verdict — PASS-with-gaps ≠ PASS.

**Exit-code contract** (when run for a hook/CI, `CONVENTIONS.md §5`): PASS/WARN → 0,
BLOCK → non-zero. The suite still advises only — it never runs `git push`.

## Step 6 — Optional: offer to gate on git push (propose, never silently add)

If no push-gate is wired and the user wants one, *offer* one of these — install only
with explicit, per-project confirmation, never touching global config, never
`--no-verify`:

**Option A — native `.git/hooks/pre-push`** (gates any push by anyone; per-clone,
not committed). A working stub that honors the exit-code contract:

```sh
#!/bin/sh
# nj-agents pre-push gate. Runs the review non-interactively; blocks on BLOCK.
# Bypass is a conscious, visible choice: `git push --no-verify`.
# Requires a non-interactive runner for the suite (e.g. `claude` headless, or your
# CI wrapper) that exits 0 on PASS/WARN and non-zero on BLOCK.
if command -v nj-agents-review >/dev/null 2>&1; then
  NJ_AGENTS_CI=1 nj-agents-review || {
    echo "pre-push-review: BLOCK — push stopped. Fix findings or use --no-verify to override." >&2
    exit 1
  }
fi
exit 0
```

(The `nj-agents-review` wrapper is whatever headless entrypoint the user wires to
run this skill in CI mode; the suite doesn't ship a binary — document the wrapper in
the repo. The hook degrades to a no-op if it's absent, so it never blocks blindly.)

**Option B — project `.claude/settings.json` `PreToolUse` hook** matching
`Bash(git push*)` — gates pushes made *through Claude*. Best for solo-Claude
workflows.

Recommend A for team-wide gating, B for solo-Claude. Present the snippet; write it
only on the user's go-ahead. Offer to add `.nj-agents-reports/` to `.gitignore` if
the report dir lives under the repo.

## Step 7 — Clean up

Remove scratch/temp files (nothing stays in the repo tree). Leave no hook, config,
or report-dir change behind unless the user opted in (Step 6). Summarize: overall
verdict + exit code, top findings per dimension, anything SKIPped or partially
reviewed that the user should check manually, and where the report was written.

## Running a single dimension

Each dimension is also standalone — `/review-secrets`, `/review-correctness`,
`/review-tests-build`, `/review-dependencies`, `/review-style` — for when you want
just one. Each prints the banner, runs the shared snapshot + hygiene + (where
applicable) secret-gate steps, then spawns its matching agent.
