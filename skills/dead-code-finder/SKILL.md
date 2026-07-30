---
name: dead-code-finder
description: Use this skill when the user asks to "find dead code", "find unused code/exports/files", "what code is unreferenced", or wants a scan for unused functions, exports, files, and dependencies. Detects the repo's own dead-code tooling at runtime (ts-prune/knip, vulture, deadcode, cargo-udeps) and degrades to a manual export-vs-import cross-reference; reports candidates with a confidence level and never deletes anything. Defaults to your uncommitted/unpushed changes to keep runs cheap; --full scans the whole tree. Works in any git repo, any language; nothing here is project-specific.
version: 0.2.0
class: review
subclass: scan
author: navjyotnishant
---

# Dead Code Finder (repo-maintenance)

Finds **unreferenced code** — unused exports, functions, files, and dependencies —
and reports candidates with a confidence signal. It **advises only: it never deletes,
comments out, or modifies anything.** A repo-maintenance skill of the **review class**
— follow `CONVENTIONS.md` (snapshot scope §1, findings format §4, CI mode §5,
report §6, safety §7).

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

Dead code is ultimately a whole-repo concern, but a whole-repo cross-reference is the
most expensive scan in this toolkit and most runs are asking about work in progress.
So it **defaults to the changed set** (`CONVENTIONS.md §1`) and takes `--full` for the
whole tree. Say which scope ran, and — when it was the changed set — say plainly that
dead code elsewhere was not looked at.

## Step 0 — Print the warning banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  DEAD-CODE FINDER — AI-ASSISTED                                  ║
╠══════════════════════════════════════════════════════════════════╣
║  Scans for unreferenced code (exports, functions, files, deps)   ║
║  and shares the findings with AI (this session + subagent). No   ║
║  external API; nothing is installed. It ADVISES only — it never  ║
║  deletes or modifies any file. Candidates carry a confidence.    ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop.
- **Source to scan.** Empty repo → report and stop.
- **No external API / no network.** A dead-code tool is used **only if already
  installed** (detected, never installed by this skill).

## Step 1 — Resolve scope

- **Changed set** (default): the snapshot (`CONVENTIONS.md §1`) — report only
  candidates in changed files. Cheap, and it answers the common question: *did the
  work I just did leave anything unreferenced?*
- **Whole-repo**: on `--full`, "scan everything", or when the snapshot is empty
  (nothing changed → the changed set would be a no-op, so survey the tree and say so).

**A changed-set result is not a clean bill of health.** Two things it cannot see, and
the report must say so rather than implying the repo is clean:

- Code elsewhere that became dead *because of* this change — deleting the last caller
  of a helper in an untouched file leaves that helper orphaned, outside the diff.
- Any pre-existing dead code in files you did not touch.

When findings look suspicious for that reason — a changed file removed a call site,
or an export lost its only import — say the whole-repo scan is worth running and
offer `--full`.

**State the scope used** in the report; don't silently pick one.

## Step 2 — Detect the repo's dead-code tooling (detect, never install)

Probe for a tool already on PATH / in the project, per ecosystem — use it if present,
else fall back:

- **TS/JS** — `knip`, `ts-prune`, `depcheck` (unused deps).
- **Python** — `vulture`.
- **Go** — `deadcode` (golang.org/x/tools), `staticcheck -unused`.
- **Rust** — `cargo-udeps` (unused deps), compiler `dead_code` warnings.
- **Other / none present** → **manual fallback:** cross-reference declared
  exports/symbols against imports/references across the tree (grep-based), and flag
  files with no inbound reference. Mark this pass **lower-confidence** than a tool.

Run any detected tool **read-only**; never install one (`CONVENTIONS.md` degrade
rule). Say which tool ran (or that the manual fallback was used).

## Step 3 — Spawn the dead-code-finder agent

Spawn `dead-code-finder` with the scope, the tool output (or the raw
export/import cross-reference), and the file tree. It classifies candidates by
confidence and **screens out known false positives** — dynamic imports, reflection,
string-keyed references, framework auto-wiring (routes, DI, decorators, entry
points), re-exports, and the repo's **public API surface** (exported for consumers,
not internally referenced).

## Step 4 — Report

Per `CONVENTIONS.md §4`/§6: a list of dead-code candidates, each with
`file:line`/symbol, **confidence** (high/medium/low), category (unused export /
unreachable function / orphan file / unused dependency), and the reason it's
suspected. Dimension verdict is informational (this is a maintenance scan, not a
gate): **candidates found** vs **none found**; a candidate is never auto-actioned.
Explicitly restate that nothing was deleted. Write the report artifact; clean up.

## Safety rails

- **Read-only, advise-only** — never delete, comment out, or modify any file (§7).
- **Detect tooling, never install it**; manual fallback always works.
- **Confidence-flag false-positive-prone cases** (dynamic dispatch, re-exports,
  public API) rather than reporting them as certain dead code.
- **State the scope** used. No secrets in the report (§6). No scratch files in the
  repo tree.
