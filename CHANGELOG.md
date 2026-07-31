# Changelog

All notable changes to **nj-agents** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Initial public release of the toolkit. Everything below describes what nj-agents
does as of this version, rather than how it was built.

### Changed

- All 25 agents now declare an explicit `tools:` allowlist. Claude Code and Cursor
  treat a missing key as inherit-all, but **Gemini CLI treats it as _no_ tools** —
  the agent loads and then cannot act — so an explicit list is the only spelling
  that means the same thing on every runner. The lists are derived per agent from
  what its body actually does: 22 of the 25 need only read tools, because they
  return content for the skill to write rather than writing anything themselves.
  `check.sh` now requires the key and fails an agent whose body claims read-only
  while its `tools:` declares a write tool.
- Review-skill banners now say "this session" rather than "this Claude session".
  **The privacy guarantee is unchanged** — the diff still goes only to the running
  session and its subagents, no external API is called, and nothing leaves the
  machine. Only the vendor name was removed, so the banner stays true whichever
  agent runs the skill.
- The note explaining where each skill finds `CONVENTIONS*.md` no longer claims
  skills live in `~/.claude/skills/`. The `readlink -f` resolution it describes
  already works from any install location — it follows the symlink back into the
  clone — so only the path claim was wrong.
- `/tech-blog`'s Dev.to publisher reads its API key and state from
  `~/.config/nj-agents/` in preference to `~/.claude/`. An existing install is
  unaffected: a file already present in the legacy location is still used, and
  `$DEVTO_API_KEY` in the environment continues to take priority over both.

### Added

**Review suite — advise only, never writes, never commits**

- `/pre-push-review` runs a secret scan as a hard first gate — it requires
  `gitleaks`, `trufflehog`, or `detect-secrets` on PATH and **BLOCKs with install
  instructions if none is present** — then runs correctness, tests/build,
  dependencies, and style in parallel, aggregating one PASS / WARN / BLOCK verdict
  plus a report artifact. Cost-aware: it states the agent count and asks before
  spawning, and skips dimensions with nothing to review.
- `/review-secrets`, `/review-correctness`, `/review-tests-build`,
  `/review-dependencies`, and `/review-style` each run standalone for a
  single-dimension check. `/review-tests-build` auto-detects the repo's own
  test/lint/build commands and never installs tooling.
- `/dead-code-finder`, `/test-gap-finder`, and `/deps-upgrade` look for accumulated
  debt — unreferenced code, uncovered code paths, available upgrades. Each detects
  the repo's own tooling first and falls back to a clearly labelled heuristic. None
  deletes code, writes a test, or upgrades a package: they report a plan.

**Authoring suite — writes one artifact, then proposes the commit**

- `/tech-blog` runs a seven-stage pipeline (writer → fact-checker → reviewer →
  editor → final-polish → platform-lint → optional poster) grounded in the real
  repo. The fact-checker **BLOCKs on any claim it cannot verify**.
- `/capture-screenshots` captures a web app, terminal, or component, detects
  PII/secrets, redacts them, and **verifies coverage before writing**. The
  un-redacted original is never committed.
- `/arch-diagram` authors presentation-quality SVG diagrams — infographic by
  default, `--sketch` for a hand-drawn variant — then renders and reviews the
  result before it ships.
- `/docs-site` produces a self-contained `docs.html`, or `--generated` for a
  multi-page site rebuilt from the source files so the docs cannot drift.
- `/changelog` builds or updates `CHANGELOG.md` in Keep a Changelog + SemVer
  format, merging into `[Unreleased]` without clobbering earlier entries.
- `/scaffold-project` lays out a new repo to the OpenSSF OSPS Baseline, delegating
  stack setup to the ecosystem's own generator (`cargo new`, `uv init`, …).

**Workflow suite — reads a diff, drafts, never runs git**

- `/pr-describe` drafts a PR title and body from the branch's delta against its base.
- `/commit-assistant` drafts Conventional Commit messages from the working tree and
  prints the exact `git add` / `git commit` block for you to run.
- `/release-notes` turns a version's changes into a **draft** GitHub Release,
  reusing the `CHANGELOG.md` section as the body when one exists.

**PM-authoring suite — proposes tracker items, never bulk-creates**

- `/pm-epic`, `/pm-story`, and `/pm-task` each draft a single item and, on opt-in,
  create it in whatever tracker is connected (Linear, Jira, Notion, GitHub Issues) —
  otherwise they hand you paste-ready markdown.
- `/pm-plan` decomposes a feature-sized ask into an Epic → Stories → Tasks tree,
  previews the **whole tree** for one approval, then creates it sequentially and
  parent-first, stopping and reporting on any partial failure.

**Social**

- `/social-post` drafts LinkedIn / X copy for a published URL. It never posts on
  your behalf.

**Verification harness**

- `check.sh` runs 16 checks over every skill and agent: frontmatter completeness,
  agent cross-references in both directions, class-contract adherence, cost and
  progress declarations, dependency documentation, and doc-sync counts. Advisory by
  default; `--strict` exits non-zero. It also scaffolds new skills and agents via
  `--new-skill` / `--new-agent`.
- A behavioural suite in `tests/` asserts the toolkit's negative contracts against
  real fixtures — leaves no files, makes no commit, spawns no agent without a
  scanner present, writes exactly one artifact. Split into an expensive local
  `run.sh` and a free `assert.sh` that CI runs.
- `bin/nj-agents-review` is a headless entry point mapping the aggregate verdict to
  exit codes (`0` PASS/WARN, `1` BLOCK, `2` harness error) for CI or a pre-push hook.
- Both the validator and the test suite **glob** `skills/*/` and `agents/*.md` —
  there is no registry to update, so a new skill is covered the moment it exists.
- GitHub Actions CI runs the validator and the assertion suite on every push; an
  optional local pre-push hook gates on the same checks.

**Guarantees shared by every skill**

- Output is grounded in the actual repo — no invented API, file, version, or
  benchmark. The human decides what gets committed. No secret is ever emitted.
  External dependencies are documented with what happens when each is absent, and a
  missing tool degrades to a fallback rather than failing.
- Cost is disclosed before any multi-agent run, and fix/verify loops stop at two
  rounds to ask rather than spending further.
- Multi-agent skills announce their agent roster up front and mark each one as it
  lands.

**Documentation**

- A published documentation site covering every suite, skill, agent, and workflow —
  generated from the same source files as the toolkit, so a page cannot disagree
  with what it documents.

[Unreleased]: https://github.com/navjyotnishant/nj-agents/commits/main
