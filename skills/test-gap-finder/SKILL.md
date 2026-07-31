---
name: test-gap-finder
description: Use this skill when the user asks to "find test gaps", "what's not covered by tests", "which code paths lack tests", or wants uncovered functions and missing edge-case tests surfaced. Detects the repo's own test/coverage tooling at runtime (jest/vitest --coverage, pytest-cov, go test -cover, cargo tarpaulin) and, when none is configured, degrades to a static source-to-test heuristic — clearly labeled as a heuristic, not measured coverage. Never writes tests or coverage config. Changed set or whole repo. Works in any git repo, any language; nothing here is project-specific.
version: 0.1.0
class: review
subclass: scan
author: navjyotnishant
---

# Test Gap Finder (repo-maintenance)

Maps code paths to existing tests and flags **coverage gaps** — uncovered functions
and missing edge-case tests. It **advises only: it never writes a test file or
coverage config, and never invents or installs a coverage tool** the repo doesn't
already use. A repo-maintenance skill of the **review class** — follow `CONVENTIONS.md`
(snapshot scope §1, findings format §4, CI mode §5, report §6, safety §7).

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

> **Every skill follows `CONVENTIONS-orchestration.md` §U** — ground everything in
> the actual repo, never run git on your own initiative, no secrets in output,
> keep `CHANGELOG.md` current when the change is user-facing, degrade rather than
> fail, and say what you did not do.

> **Spawning subagents — `CONVENTIONS-orchestration.md`.** This skill spawns agents,
> so `§C` (cost) and `§R` (progress reporting) apply. **Cost shape:** 1–2 agent calls.
> State it and get a yes before the first dispatch; cap fix rounds at 2; halt on any
> signal to stop. Announce the **pipeline** up front and each stage as it starts, so a stall is
> attributable to a named stage (`§R`).


## Dependencies

Detected at runtime, never installed by this skill (`§A5`).

| Tool | Used for | Without it |
|---|---|---|
| the repo's coverage tool (`--coverage`, `pytest-cov`, `go test -cover`, `tarpaulin`) | measured coverage | a static source-to-test heuristic, **labelled as a heuristic** |

## Step 0 — Print the warning banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  TEST-GAP FINDER — AI-ASSISTED                                   ║
╠══════════════════════════════════════════════════════════════════╣
║  Maps code paths to tests and flags gaps, sharing findings with  ║
║  AI (this session + subagent). No external API; no tool is       ║
║  installed. It ADVISES only — it never writes tests or coverage  ║
║  config. Without a coverage tool it uses a labeled heuristic.    ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop.
- **A test suite.** If the repo has **no tests at all**, report **SKIP — no test
  suite found** (that's a different problem than a gap) and stop.
- **No external API / no network.** A coverage tool is used **only if already
  configured** — detected, never installed.

## Step 1 — Resolve scope

- **Changed set** (default when there's a diff): the snapshot (`CONVENTIONS.md §1`) —
  flag gaps in code the current work touches (the highest-value case before a push).
- **Whole-repo**: on request, or when there's no diff — survey the whole tree.

State the scope used.

## Step 2 — Detect the repo's test/coverage tooling (detect, never install)

Reuse the auto-detection discipline of `review-tests-build` (see
`tests-build-runner`) and extend it to coverage. Probe, per stack:

- **Node** — `jest --coverage`, `vitest --coverage`, `nyc`; coverage config in
  `package.json`/`jest.config`/`vitest.config`.
- **Python** — `pytest --cov` (pytest-cov), `coverage.py`.
- **Go** — `go test -cover` / `-coverprofile`.
- **Rust** — `cargo tarpaulin`, `llvm-cov`.
- **JVM** — JaCoCo. **Ruby** — SimpleCov.

**Do not install or configure** any of these. If one is already configured, run it
**read-only** (or parse an existing coverage report) to find uncovered lines/functions
in scope.

## Step 3 — Fallback when no coverage tool exists (labeled heuristic)

If no coverage tooling is present, degrade to a **static heuristic**: map each source
function/export in scope to a probable test by naming/import convention
(`foo.py`→`test_foo.py`, `Bar.ts`→`Bar.test.ts`, a test importing the module), and
flag source paths with **no discoverable corresponding test**.

**Label this clearly as a heuristic, not measured coverage** — it finds *untested-by
-convention* code, and can't see whether an existing test actually exercises a branch.

## Step 4 — Spawn the test-gap-finder agent

Spawn `test-gap-finder` with the scope, the coverage output **or** the heuristic
source→test map, and the source. It distinguishes:

- **Uncovered function/path** — code with no test exercising it, and
- **Missing edge-case test** — a covered function whose **error branches, boundary
  conditions, or null/empty inputs** appear untested, where inferable from the code's
  own branching.

## Step 5 — Report

Per `CONVENTIONS.md §4`/§6: gaps as a list — `file:line`/function, gap type
(uncovered path / missing edge case), and (for measured coverage) the number. State
**measured coverage vs heuristic** explicitly. Verdict is informational (maintenance
scan): **gaps found** vs **none in scope**. Never writes a test. Write the report
artifact; clean up.

## Safety rails

- **Read-only, advise-only** — never write a test file or coverage config (§7).
- **Detect tooling, never install/configure it**; the heuristic fallback is always
  labeled as such, never presented as measured coverage.
- **SKIP, don't fabricate**, when there's no test suite at all.
- **State the scope**. No secrets in the report (§6). No scratch files in the repo.
