---
name: review-tests-build
description: Use this skill when the user asks to "run the tests before I push", "check the build", "run lint on my changes", or wants the project's test/lint/build commands run as a gate over the current changes. Auto-detects the right commands for whatever stack the repo uses (Node, Python, Go, Rust, JVM, Make/just, or commands documented in CLAUDE.md/AGENTS.md) — never hardcodes one project's stack. Works in any git repo.
version: 0.3.0
class: review
subclass: gate
author: navjyotnishant
---

# Review: Tests & Build

Runs the project's own **test / lint / build** commands as a gate over the
current changes, then reports pass/fail. The commands are **discovered per repo**
— this skill mirrors the "discover per repo, don't assume a prior repo's answers"
philosophy and never hardcodes a stack, port, or command.

Follow the shared rules in `CONVENTIONS.md` (CI mode §5, report §6, safety §7).

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

## Step 0 — Print the warning banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  TESTS & BUILD REVIEW                                             ║
╠══════════════════════════════════════════════════════════════════╣
║  This DETECTS and RUNS your project's own test/lint/build         ║
║  commands. It never installs tooling and never modifies your      ║
║  code. Command output may be shared with AI (this session) to     ║
║  summarize failures. This tool ADVISES only — it never pushes.    ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop.
- **Optional, auto-detected:** a test / lint / build command. If none is found,
  this dimension reports **SKIP** (not a false PASS) — it never invents one and
  never installs tooling.
- **No external API key** — uses the current Claude session.

## Step 1 — Detect the commands (first hit per category; documented beats inferred)

Discover freshly each run. Prefer a command the project explicitly documents
over one you infer:

1. **Documented** — grep `CLAUDE.md` / `AGENTS.md` / `README` for a stated
   "how to test / lint / build" command. The project's own words win.
2. **Node** — `package.json` `scripts`: keys matching `test`, `lint`, `build`,
   `typecheck`. Manager from the lockfile: `pnpm-lock.yaml`→pnpm,
   `yarn.lock`→yarn, else npm.
3. **Task runners** — `justfile` (`just --summary`), `Makefile` (`test`/`lint`/
   `build` targets), `Taskfile.yml`.
4. **Python** — `pyproject.toml` / `tox.ini` / `pytest.ini` / `setup.cfg` →
   `pytest`, `ruff`/`flake8`, `mypy`.
5. **Go** — `go.mod` → `go test ./...`, `go vet ./...`, `go build ./...`.
6. **Rust** — `Cargo.toml` → `cargo test`, `cargo clippy`, `cargo build`.
7. **JVM** — `build.gradle(.kts)` → `./gradlew test`; `pom.xml` → `mvn test`.

If multiple ecosystems coexist, prefer the one touched by the diff. Report which
commands you detected before running them.

## Step 2 — Run the detected commands

Run the detected test / lint / build commands as-is. Rules:

- **Never install anything** — missing tooling is reported, not `npm install`-ed
  or `pip install`-ed. If a command's tool is absent, that sub-check is SKIP.
- **Never modify code** to make something pass.
- Capture exit codes and the tail of output for any failure.

## Step 3 — Report

For each command: PASS (exit 0) / FAIL (non-zero, with the failing summary) /
SKIP (not detected or tool absent). Dimension verdict: **BLOCK** if any detected
command fails, **PASS** if all detected commands pass, **SKIP** if nothing was
detected at all (never a false PASS).

This dimension is the cheap one — running the repo's own commands costs no agent
at all. Keep it that way: report the raw pass/fail first, and spawn the
`tests-build-runner` agent **only** when a failure genuinely needs triage and the
output does not already explain itself (`CONVENTIONS.md §8`). A compiler error
naming a file and line needs no agent to interpret it. Honor the CI-mode exit-code
contract (`CONVENTIONS.md §5`) and write the report artifact (§6) if run
standalone. Advises only — never pushes, never installs, never modifies code.

## Remembering what you learned (optional)

If the repo doesn't document its test/lint/build command clearly, consider
*proposing* (never silently adding) a short note to `CLAUDE.md` / `AGENTS.md` so
future runs — or other tools — don't re-derive it. Only add such a note with the
user's go-ahead; it's a durable repo change, not a one-off.
