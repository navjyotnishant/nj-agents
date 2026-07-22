---
name: deps-upgrade
description: Use this skill when the user asks to "check for dependency upgrades", "what packages are outdated", "survey my dependencies for updates", or wants an upgrade plan for stale packages. Surveys the WHOLE current dependency manifest for available upgrades, flags each with a semver risk class and breaking-change signals, and proposes a prioritized upgrade plan — it never runs the upgrade or edits the manifest. Detects the repo's package manager at runtime; zero-network by default. Works in any git repo and any package ecosystem; nothing here is project-specific.
version: 0.1.0
---

# Dependency Upgrade Survey (repo-maintenance)

Surveys the project's **current dependency manifest** for available upgrades, flags
each with a risk class and breaking-change signals, and proposes a prioritized
**upgrade plan**. It **advises only: it never runs the upgrade, and never edits the
manifest or lockfile.** A repo-maintenance skill of the **review class** — follow
`CONVENTIONS.md` (findings format §4, CI mode §5, report §6, safety §7).

> **How this differs from `/review-dependencies`.** `/review-dependencies` reviews the
> dependency **changes in a diff** (a governance gate on what you just added/upgraded).
> `/deps-upgrade` surveys the **whole current manifest** for upgrades *available* but
> not yet taken — a maintenance survey, not a diff review. Different question, different
> scope. Don't conflate them.

## Step 0 — Print the warning banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  DEPENDENCY UPGRADE SURVEY — AI-ASSISTED                         ║
╠══════════════════════════════════════════════════════════════════╣
║  Surveys your current manifest for available upgrades and shares  ║
║  it with AI (this session + subagent) to assess risk. It ADVISES ║
║  only — it never runs an upgrade or edits a manifest/lockfile.    ║
║  Zero-network by default; any registry check is called out.      ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop.
- **A dependency manifest.** None found → report **SKIP — no manifest** and stop.
- **No external API key.** Zero-network by default — see Step 2.

## Step 1 — Detect the ecosystem and read the manifest

Detect the package manager(s) present and read the **human-authored** manifest +
lockfile (the same per-ecosystem list `review-dependencies` uses):

- **Node** — `package.json` (+ lock). **Python** — `pyproject.toml`/`requirements*`.
- **Go** — `go.mod`. **Rust** — `Cargo.toml`. **Ruby** — `Gemfile`.
- **PHP** — `composer.json`. **JVM** — `build.gradle`/`pom.xml`. **.NET** — `*.csproj`.

## Step 2 — Determine available upgrades (network is opt-in, not silent)

Knowing what's *available* generally needs a version lookup. Be explicit about the
network posture (`CONVENTIONS.md` — the suite is zero-network by default):

- **Default (no network):** parse the lockfile / installed versions and report the
  **current pinned state**, flagging that "latest available" is **unknown without a
  registry check." Still useful: floating ranges, very old pins, and known-EOL majors
  are visible from the manifest alone.
- **On explicit user opt-in**, and only if the package manager is already installed,
  run its **own** outdated command read-only: `npm outdated`, `pip list --outdated`,
  `go list -u -m all`, `cargo outdated` (if present), `bundle outdated`,
  `composer outdated`. **Say clearly** that this makes the package manager's own
  network call. Never install a tool to do it.

## Step 3 — Spawn the deps-upgrade agent

Spawn `deps-upgrade` with the manifest, current versions, and (if opted-in) the
outdated output. It classifies each outdated dependency by **semver bump** (patch /
minor / major) and derives a **breaking-change signal** where it honestly can —
without inventing unverifiable claims. It is a **distinct** agent from
`dependency-reviewer` (survey vs. diff-review are different jobs).

## Step 4 — Report + propose the plan

Per `CONVENTIONS.md §4`/§6: a table (package · current · latest-available-or-`?` ·
bump class · breaking-change signal), then a **prioritized upgrade plan** —
**safe patches → minors → majors flagged for manual review**. The plan is **advisory
output** (markdown/report), *not* a manifest edit and *not* a persisted repo file.
Verdict is informational: **upgrades available** vs **up to date** vs **SKIP**.
Restate: nothing was upgraded or edited. Write the report artifact; clean up.

## Safety rails

- **Never run the upgrade; never edit the manifest or lockfile** — advisory plan only
  (§7). No `npm update`/`pip install -U`/`cargo update`/etc.
- **Zero-network by default**; a live outdated-check is **opt-in, uses the package
  manager's own network call, and is stated plainly** — never silent.
- **Detect the package manager, never install one.**
- **Ground the risk assessment** — no fabricated "this breaks X" without a signal
  (major bump / local CHANGELOG). No secrets in the report (§6).
