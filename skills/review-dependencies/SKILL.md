---
name: review-dependencies
description: Use this skill when the user asks to "check my dependency changes", "review new packages before I push", "did I add any risky dependencies", or wants a governance review of dependency and license changes in the current commit or uncommitted work. Flags added/removed/upgraded dependencies, license changes, and supply-chain risk signals in the diff. Works in any git repo and any package ecosystem; nothing here is project-specific.
version: 0.3.0
class: review
subclass: gate
author: Navjyot Nishant
---

# Review: Dependencies & Licenses

Governance review of **dependency and license changes** introduced by the current
commit or uncommitted work — a standard gate before code (and its new supply chain)
leaves a machine. It flags what was added, removed, or upgraded, and surfaces
license and supply-chain risk signals.

Follow the shared rules in `CONVENTIONS.md` (snapshot scope §1, findings format §4,
CI mode §5, report §6, safety §7).

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
║  DEPENDENCIES & LICENSES REVIEW — AI-ASSISTED                    ║
╠══════════════════════════════════════════════════════════════════╣
║  This inspects dependency-manifest changes in your diff and       ║
║  shares them with AI (this Claude session + subagent) to assess   ║
║  added packages, upgrades, and license changes. No external API   ║
║  is called; no package is installed or fetched. ADVISES only.     ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop.
- **A diff to review**; if empty, report and stop.
- **No external API key**, **no network** — this reviews the diff only. It does not
  install packages, hit a registry, or run an audit tool that fetches remotely
  unless the user explicitly asks and such a tool is already installed.

## Step 1 — Find the dependency-manifest changes

From the snapshot (`CONVENTIONS.md §1`), pick out changes to dependency manifests —
the **human-authored** side, discovered per ecosystem:

- **Node** — `package.json` (deps/devDeps/peer/optional). (`package-lock.json`/
  `yarn.lock`/`pnpm-lock.yaml` corroborate exact versions but aren't reviewed line
  by line — see `CONVENTIONS.md §2`.)
- **Python** — `pyproject.toml`, `requirements*.txt`, `setup.cfg`, `Pipfile`.
- **Go** — `go.mod` (and `go.sum` for the resolved graph).
- **Rust** — `Cargo.toml` (`Cargo.lock` for versions).
- **Ruby** — `Gemfile`. **PHP** — `composer.json`. **JVM** — `build.gradle(.kts)`,
  `pom.xml`. **.NET** — `*.csproj`, `packages.config`.
- **Container / CI** — `Dockerfile` base-image changes, GitHub Actions
  `uses:` pins.

If the diff changes no manifests, report **SKIP — no dependency changes** and stop.

## Step 2 — Spawn the dependencies agent

**Cost check first (`CONVENTIONS.md §8`).** Step 1 has already stopped if no
manifest changed — that free, accurate skip is the main cost saving here. Before
spawning, state the scope in one line — `Reviewing 2 manifest changes with 1
dependency agent.` — and never re-run more than twice on the same change without
being asked.

Spawn `dependency-reviewer` with the manifest changes (and the corroborating
lockfile deltas as context). It assesses:

- **Added dependencies** — is each one necessary, reputable, and reasonably
  maintained? Typosquat / lookalike names (a classic supply-chain vector). Does a
  small utility pull in a large or risky transitive tree?
- **Version changes** — major-version bumps (breaking-change risk), and
  suspicious *downgrades* or pins to an odd version. Un-pinned/floating ranges
  (`*`, `latest`, broad `^`/`~`) added where the repo otherwise pins.
- **License changes** — a new dependency (or an upgrade) that introduces a
  copyleft/strong-copyleft (GPL/AGPL) or an unusual/unknown license into a project
  that's otherwise permissive (MIT/Apache/BSD). Flag for legal/governance review —
  it advises, it does not adjudicate license compatibility.
- **Removals** — a removed dependency whose code still appears used in the diff.
- **Integrity signals** — a changed registry/source URL, a git/URL dependency
  replacing a registry one, a disabled integrity/lockfile check.

## Step 3 — Report

Per `CONVENTIONS.md §4`/§6: a concise table of dependency changes
(added / removed / upgraded, old→new version, license if determinable) plus
findings (≥80 confidence). Dimension verdict: **BLOCK** for a clear risk (typosquat,
a strong-copyleft license entering a permissive codebase without acknowledgement, a
removed dep still in use), **WARN** for things to double-check (major bump, floating
range), **PASS** if changes are clean, **SKIP** if no manifests changed. Advises
only — never installs or modifies. Write the report artifact; clean up.
