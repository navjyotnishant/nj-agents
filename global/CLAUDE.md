# Global guidance — nj-agents SDLC toolkit

<!--
  Source of truth: <nj-agents repo>/global/CLAUDE.md
  Installed to ~/.claude/CLAUDE.md as a SYMLINK by nj-agents/install.sh.
  Edit it in the repo, not here. Repo: github.com/navjyotnishant/nj-agents
-->

A personal toolkit of Claude Code **skills and agents** covering the software
development lifecycle is installed globally on this machine — **16 skills, 22
agents**. It is **project-agnostic**: every skill works in any git repo, any stack,
any language, and discovers per-repo details at runtime rather than assuming a
stack, path, port, or tool.

These skills exist so recurring SDLC work is done consistently instead of ad-hoc.
**Prefer the matching skill over improvising the same task by hand.** Suggest one
when the user's request matches; do not fire them unprompted.

## Review suite — advise only, leave no files, never commit

Reviews the *current commit or uncommitted changes* (staged + unstaged +
committed-but-unpushed). Five dimensions, each a skill + agent pair, plus an
umbrella that runs them all.

| Skill | What it does | Agent |
|---|---|---|
| `/pre-push-review` | **Umbrella.** Secret scan as a gate, then the rest in parallel; aggregates one PASS / WARN / BLOCK verdict + report artifact. | orchestrates the below |
| `/review-secrets` | Scanner over the diff **first** as a hard gate, then a semantic security pass. | `secrets-reviewer` |
| `/review-correctness` | Bugs, regressions, edge cases, missing validation in changed lines + blast radius. | `correctness-reviewer` |
| `/review-tests-build` | Auto-detects and runs the repo's own test/lint/build commands. Never installs tooling. | `tests-build-runner` |
| `/review-dependencies` | Added/upgraded packages, pinning risk, license changes, typosquatting. Diff-only. | `dependency-reviewer` |
| `/review-style` | Consistency with surrounding code, commit-message hygiene, leftover debug/TODO. | `style-reviewer` |

Each runs standalone; the umbrella runs them together. Shared behavior lives in the
repo's `CONVENTIONS.md`.

**Secret scanning is a hard requirement.** `/review-secrets` and the umbrella need
`gitleaks`, `trufflehog`, or `detect-secrets` on PATH and **BLOCK with install
instructions** if none is present — there is no heuristic-only fallback. On a hit the
review **stops and shares nothing**. (`gitleaks` is installed on this machine.)

## Authoring suite — writes one artifact, then PROPOSES the commit

| Skill | What it does | Agents |
|---|---|---|
| `/changelog` | `CHANGELOG.md` in Keep a Changelog + SemVer from commit history. Merges into `[Unreleased]` without clobbering; suggests the bump. (For the GitHub **Release** object, see `/release-notes`.) | `changelog-writer` |
| `/arch-diagram` | System/solution/sequence/data-flow/deployment/ER diagrams into `docs/architecture/`. | `diagram-architect`, `diagram-qa` |
| `/capture-screenshots` | Capture → detect PII/secrets → blur/mask → **verify coverage before writing**. | `screenshot-capturer`, `sensitive-data-reviewer`, `screenshot-redactor` |
| `/docs-site` | Self-contained theme-aware `docs.html` from docs, code, an outline, or SKILL.md/OpenAPI/JSON-Schema. Auto-derives the menu; flags gaps rather than inventing. | `docs-architect`, `docs-designer` |
| `/tech-blog` | writer → fact-checker → reviewer → editor → final-polish → platform-lint → optional poster. Generates its own diagrams/screenshots, then embeds them. | `blog-writer`, `blog-fact-checker`, `blog-reviewer`, `blog-editor`, `blog-final-polish`, `blog-platform-lint`, `blog-poster` |
| `/scaffold-project` | Lay out a **new** repo to the OpenSSF OSPS Baseline (Level 1 default), delegating stack layout to the ecosystem generator (`cargo new`/`uv init`/…). Cites each file by control ID; verifies before reporting done. | (no dedicated agent) |
| `/social-post` | LinkedIn / X copy for a **published** URL — short / medium / builder-story, hook-first, clean hashtags. Never writes to the repo, never auto-posts. | `social-post` |

Shared behavior lives in the repo's `CONVENTIONS-authoring.md` (§A1 repo-ingest,
§A2 scoped output, §A3 propose-commit, §A4 placement, §A5 MCP-detect-never-require,
§A6 grounding/safety, §A7 idempotent).

Two gates worth knowing: `/tech-blog`'s **fact-checker BLOCKS** on any claim it
can't verify against the repo, and `/arch-diagram` runs a mandatory
**render → QA → fix loop** through `diagram-qa` until the diagram PASSES.

## Workflow suite — reads the diff, drafts a change artifact, proposes (never auto-acts)

| Skill | What it does | Agent |
|---|---|---|
| `/pr-describe` | Drafts a PR **title + body** from the branch's delta vs its base (the PR view). Fills the repo's own PR template when present; grounds every line in a real commit/hunk. Opens a **draft** PR only if you opt in and `gh` is present; else hands you the text. **Never pushes, never opens a non-draft PR, never merges.** | `pr-describer` |
| `/commit-assistant` | Drafts Conventional Commits message(s) from the working-tree changes and prints the `git add` + `git commit` block. Splits unrelated changes into separate commits; respects existing staging. **Never runs git** — the human decides what gets committed. | (no dedicated agent) |
| `/release-notes` | Turns a version's changes into a **draft GitHub Release** — reuses the `CHANGELOG.md` section as the body (composes with `/changelog`), else summarizes the commit delta. Drafts `gh release create --draft`; **never publishes, never pushes a tag.** | (no dedicated agent) |

Reads a diff like the review class but invents nothing; proposes like the authoring
class (§A3) but its artifact is a **PR, not a repo file** — so it never writes to
`docs/`. `gh` is detected, never required (§A5).

## PM-authoring suite — writes a work item into a tracker, PROPOSES the create *(planned)*

Foundation shipped (`CONVENTIONS-pm.md`); the skills are not built yet — do not try to
invoke `/pm-*` until they land. Planned: `/pm-epic`, `/pm-story`, `/pm-task`, and the
`/pm-plan` orchestrator (sequential Epic→Stories→Tasks). Tool-agnostic (Linear / Jira /
Notion / GitHub Issues via a connected MCP), draft-first, MCP-detect-never-require, with
a paste-ready-markdown fallback. This is what the "track work in a PM tool" standing
rule will use to create the tracked item.

## Standing rules

Apply these to related work even when no skill is invoked:

- **The human decides what gets committed.** Never `git add`, `commit`, `push`, or
  `tag` on your own initiative — write the artifact and propose the exact commands.
  An explicit "commit and push" from the user overrides this.
- **No `Co-Authored-By` trailers.** Do not add a `Co-Authored-By:` line (or any
  "Generated with" attribution) to commit messages you write or propose. This is the
  default across this user's repos; a project whose own `CLAUDE.md` asks for
  attribution overrides it.
- **Confirm the staged set before committing.** When proposing a commit, run
  `git diff --cached --stat` and check that only the intended files are staged — flag
  anything unexpected rather than committing it.
- **Self-review before pushing.** Before proposing a push, do a quick pass over the
  changes for bugs, regressions, missing validation, and security issues — or offer
  `/pre-push-review` for the full gate.
- **Stash unrelated WIP before switching branches.** When in-progress changes in one
  area aren't ready, stash them explicitly (`git stash push -m "…" -- <paths>`) before
  a branch switch so they don't ride along into an unrelated commit or merge.
- **Track the work in a PM tool before non-trivial code.** For a real task, bug fix,
  or feature (not a throwaway experiment), there should be a tracked item — in
  **whatever project-management tool the project uses**: Linear, Jira, GitHub Issues,
  Notion, etc. First check for one that matches; if none exists, **offer to create it**
  in the connected PM tool (once the PM-authoring skills land, via `/pm-story` /
  `/pm-plan`) and reference its key in the branch name and commits. This is
  tool-agnostic and **detect-never-require**: if no PM tool is connected, or the user
  declines, or it's a throwaway repo, note that and proceed — never hard-block coding
  on a ticket. A project whose own `CLAUDE.md` mandates a stricter gate (e.g. "no code
  without an issue") overrides this softer default.
- **Ground everything in the actual repo.** Read README/docs/code; never invent an
  API, file path, version, or benchmark. Unverifiable claims get cut or marked.
- **Degrade, don't fail.** External tools and MCP connectors are detected at runtime,
  never required; every path has a zero-dependency fallback. The sole exception is
  secret scanning, which genuinely blocks without a scanner.
- **Scoped output.** Artifacts go to conventional locations (`CHANGELOG.md`,
  `docs/`, `docs/blog/`, `docs/architecture/`). Working notes go to a scratchpad or
  temp dir — **never** into the repo tree.
- **Never commit un-redacted screenshots.** The raw capture stays gitignored; only
  the verified-redacted image ships.
- **Nothing leaves the machine.** Analysis runs in the current Claude session — no
  external API. External posting happens only via an MCP the user opted into, as a
  draft.

## Operational notes

- **CI / non-interactive:** `NJ_AGENTS_CI=1` (or `--ci`) runs without prompts;
  ambiguity resolves to BLOCK. Exit `0` for PASS/WARN, non-zero for BLOCK.
- **Report artifact:** each umbrella run writes to
  `${NJ_AGENTS_REPORT_DIR:-<repo>/.nj-agents-reports}/`. Never committed.
- **Push gating is opt-in and per-project**, never global — a `.git/hooks/pre-push`,
  or a `PreToolUse` hook matching `Bash(git push*)`. `/pre-push-review` offers to
  set one up; never install one silently.

## Suggesting a skill

Good: user is wrapping up a change → offer `/pre-push-review` before they push.
They ask for release notes → use `/changelog` rather than hand-writing a commit list.
They ask how the system fits together → offer `/arch-diagram`.

Not good: invoking a skill for a task it doesn't cover, or running one silently as a
side effect of an unrelated request.

**A project's own `CLAUDE.md` takes precedence over this file.**
