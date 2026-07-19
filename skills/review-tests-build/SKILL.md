---
name: review-tests-build
description: Use this skill when the user asks to "run the tests before I push", "check the build", "run lint on my changes", or wants the project's test/lint/build commands run as a gate over the current changes. Auto-detects the right commands for whatever stack the repo uses (Node, Python, Go, Rust, JVM, Make/just, or commands documented in CLAUDE.md/AGENTS.md) — never hardcodes one project's stack. Works in any git repo.
version: 0.1.0
---

# Review: Tests & Build

Runs the project's own **test / lint / build** commands as a gate over the
current changes, then reports pass/fail. The commands are **discovered per repo**
— this skill mirrors the "discover per repo, don't assume a prior repo's answers"
philosophy and never hardcodes a stack, port, or command.

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
detected at all. For deeper failure triage, `tests-build-runner` (agent) can
analyze the output. Advises only — never pushes.

## Remembering what you learned (optional)

If the repo doesn't document its test/lint/build command clearly, consider
*proposing* (never silently adding) a short note to `CLAUDE.md` / `AGENTS.md` so
future runs — or other tools — don't re-derive it. Only add such a note with the
user's go-ahead; it's a durable repo change, not a one-off.
