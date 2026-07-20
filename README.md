# nj-agents

A personal, project-agnostic collection of Claude Code **skills and agents** for
software-development workflows. Maintained independently and installed into any
project (or globally) via symlink. Designed to grow — new skills/agents drop into
`skills/` and `agents/` and are picked up on the next install.

## Two classes of skill

nj-agents has two kinds of skill, with opposite stances on touching your repo:

- **Review class** — *advise only, leave no files, never commit.* Reads your changes
  and reports. Shared rules: [`CONVENTIONS.md`](CONVENTIONS.md).
- **Authoring class** — *writes an artifact into the repo* (changelog, diagram, blog),
  then **proposes** the commit (never runs `git add`/`commit`/`push`/`tag`). Shared
  rules: [`CONVENTIONS-authoring.md`](CONVENTIONS-authoring.md).

Both share one rule: **the human decides what gets committed.**

## Review suite (review class)

A thorough, AI-assisted review of your *current commit or uncommitted changes* before
you push (or any time, on demand, or from CI). Five dimensions, each a dedicated
skill + agent pair, plus one umbrella that runs them all.

| Skill | What it does | Agent it uses |
|---|---|---|
| `/pre-push-review` | **Umbrella.** Prints the warning banner, runs the secret scan as a gate, then spawns the other dimensions in parallel and aggregates one PASS / WARN / BLOCK verdict + a report artifact. | (orchestrates the below) |
| `/review-secrets` | Secret scan over the diff **first** (hard gate — shares nothing if a key is found), using a **required** dedicated scanner (gitleaks/trufflehog/detect-secrets — BLOCKs with install steps if none is present). Then a semantic security pass. | `secrets-reviewer` |
| `/review-correctness` | Bugs, regressions, edge cases, missing validation in the changed lines and their blast radius. | `correctness-reviewer` |
| `/review-tests-build` | Auto-detects and runs the repo's own test/lint/build commands as a gate. Never installs tooling. | `tests-build-runner` |
| `/review-dependencies` | Added/removed/upgraded packages, version-pinning risk, license changes, supply-chain signals (typosquatting). Diff-only; no network, no install. | `dependency-reviewer` |
| `/review-style` | Consistency with surrounding code, commit-message hygiene, leftover debug/TODO output. | `style-reviewer` |

Each dimension runs standalone; the umbrella runs them together. Shared behavior
(snapshot scope, diff hygiene, findings format, CI mode, report artifact, safety
rails) lives once in [`CONVENTIONS.md`](CONVENTIONS.md).

## Authoring suite (authoring class)

Generates documentation artifacts from your project and places them in the repo, then
proposes the commit. Every skill reads the repo to ground its output — nothing is
invented — and prints a banner before it starts.

| Skill | What it does | Agent(s) it uses |
|---|---|---|
| `/changelog` | Generates/updates `CHANGELOG.md` in **Keep a Changelog** format + SemVer, from your commit history (Conventional Commits as the signal). Suggests the version bump, merges into `[Unreleased]` without clobbering, proposes the commit (+ optional release-only tag). | `changelog-writer` |
| `/arch-diagram` | Reads your README/docs/ADRs, then generates a system/solution/sequence/data-flow/deployment/ER diagram. Default **Excalidraw + exported SVG** (mermaid / inline SVG / Figma-via-MCP on request); places it in `docs/architecture/` and proposes the commit. | `diagram-architect` |
| `/docs-site` | **Multi-agent** universal documentation generator. Builds a self-contained, theme-aware `docs.html` from existing docs, the codebase, an outline, or structured definition files (SKILL.md/OpenAPI/JSON-Schema). Auto-derives the menu from the content, grounds everything in the source (flags gaps rather than inventing), and embeds **auto-redacted** screenshots via `/capture-screenshots`. Proposes the commit. | `docs-architect`, `docs-designer` |
| `/capture-screenshots` | **Multi-agent** capture + **redaction** pipeline. Captures from a running web app (Playwright), terminal/CLI output, a static HTML/component, or existing images; then detects PII/secrets (emails, tokens, keys, phone, cards, names), blurs/masks them (full for high-risk, partial for illustrative), and **verifies coverage before writing** (blocks if unsure). Only the redacted image is committed — the raw stays gitignored. | `screenshot-capturer`, `sensitive-data-reviewer`, `screenshot-redactor` |
| `/tech-blog` | **Multi-agent** pipeline (writer → fact-checker → reviewer → editor → final-polish → platform-lint → optional poster) that writes an expert technical post about the project. The **fact-checker BLOCKS** on any claim it can't verify against the repo. **Generates** the visual assets it needs (arch diagrams via `/arch-diagram`, redacted screenshots via `/capture-screenshots`) alongside the writer, then embeds them; applies an emphasis/terminology/style pass, runs a pre-publish checklist (single-H1, ending, dupes) and a platform lint (Dev.to tags/SVG→PNG/cover), writes to `docs/blog/` + publish-ready MD/HTML, posts via a connected MCP you opt into — or, for Dev.to with no MCP, a direct-REST fallback (`DEVTO_API_KEY`, draft-first). | `blog-writer`, `blog-fact-checker`, `blog-reviewer`, `blog-editor`, `blog-final-polish`, `blog-platform-lint`, `blog-poster` |
| `/social-post` | Drafts promo copy (LinkedIn / X) for a **published** post/repo/demo, grounded in the actual content. Short / medium / builder-story variants, hook-first, correct link-preview + first-comment strategy, clean hashtags. Honors style prefs (e.g. no em-dashes). Drafts only — never auto-posts. | `social-post` |

Shared authoring behavior (repo-context ingest, placement, propose-commit,
MCP-detection, grounding/safety) lives once in
[`CONVENTIONS-authoring.md`](CONVENTIONS-authoring.md).

## ⚠️ What it does with your code — read this

**Review suite:** these skills **generate a snapshot of your changes** (the `git diff`
of your staged, unstaged, and committed-but-unpushed work) and **share it with AI** —
the Claude session running the skill, plus the subagents it spawns — to review it.
**No external API is called**; the current session does the analysis. Every skill
prints a banner saying so before it reads anything. **A local secret scan runs before
any snapshot is shared** — on a hit the review **stops and shares nothing** until you
remove it. The review suite **advises only**: it never pushes, commits, bypasses git
hooks, or leaves files in your repo.

**Authoring suite:** these skills read your repo to ground their output and **do write
one artifact into it** (a changelog, diagram, or blog post) at a standard docs
location. They then **propose** the commit — showing you the diff and the exact
`git add`/`commit`/`push` commands — but **never run git themselves**. Posting a blog
externally happens only through an MCP connector you've explicitly opted into, as a
draft, never an auto-publish. Nothing is invented: every fact traces to your repo (the
blog fact-checker blocks on anything it can't verify). Screenshots are **redacted by
default** — PII/secrets are detected and blurred, coverage is verified before the
image is written, and only the redacted version is committed (the raw capture stays in
a gitignored dir).

## Prerequisites

- **Claude Code**, and a **git repository** to review (`git` on PATH).
- **A diff to review** — if there's nothing staged/unstaged/unpushed, the skills
  stop cleanly.
- **No API key required, no network** — the review uses your current Claude session.
- **Required:** a dedicated secret scanner on PATH — [`gitleaks`](https://github.com/gitleaks/gitleaks)
  (MIT), [`trufflehog`](https://github.com/trufflesecurity/trufflehog) (Apache-2.0),
  or [`detect-secrets`](https://github.com/Yelp/detect-secrets) (Apache-2.0) — any
  one. `review-secrets` and the umbrella **BLOCK with install instructions** if none
  is present; there is no heuristic-only fallback. All three are free/open source:
  `brew install gitleaks` (or `trufflehog`), or `pipx install detect-secrets`.
- **Optional:** a test/lint/build command. `review-tests-build` auto-detects it
  (Node/Python/Go/Rust/JVM/Make/just, or a command documented in
  `CLAUDE.md`/`AGENTS.md`). If none exists, that dimension reports SKIP — it never
  invents or installs one.

## Data handling / privacy

Nothing leaves your machine. The suite reads your git diff and analyzes it with the
**Claude session already running** — no external API is called, no third-party
service receives your code. Before any diff is shared even with a subagent, the
secret scan runs; on a hit it stops and shares nothing. Report artifacts are written
outside the repo tree (or under a gitignored dir) and contain **no unmasked
credentials**. See [`CONVENTIONS.md`](CONVENTIONS.md) §3/§6/§7.

## CI / non-interactive use

Set `NJ_AGENTS_CI=1` (or pass `--ci`) to run without prompts, suitable for a
pipeline or git hook. In CI mode the review never waits for confirmation — any
ambiguity resolves to the safe (BLOCK) outcome — and honors an **exit-code
contract**: `0` for PASS/WARN, non-zero for BLOCK. A wired hook or CI step keys off
that code. The suite itself still only advises — it never runs `git push` and never
bypasses a hook.

## Report artifact

Each umbrella run writes a timestamped record — repo, branch, scope reviewed, which
secret scanner ran, files excluded, per-dimension verdicts + findings, and the
aggregate verdict — to `${NJ_AGENTS_REPORT_DIR:-<repo>/.nj-agents-reports}/` (or the
temp dir). It is **never committed**; the umbrella offers to add
`.nj-agents-reports/` to your `.gitignore`.

## Install

Global (all projects):

```bash
./install.sh
```

Per-project (into `DIR/.claude/`):

```bash
./install.sh --project /path/to/your/repo
```

Uninstall (only removes symlinks pointing back into this repo):

```bash
./install.sh --uninstall
./install.sh --project /path/to/your/repo --uninstall
```

Restart / reload Claude Code afterward, then run `/pre-push-review` in any repo.
The installer uses **symlinks**, so editing files here updates every install.

## Optional: gate on `git push`

By default the suite is **manual / on-demand** — nothing auto-fires. If you want it
to gate an actual push, wire one of these **per project** (never globally, and the
suite proposes it, never installs silently):

- **Native git hook** — a `.git/hooks/pre-push` that runs the review and exits
  non-zero on BLOCK. Gates any push by anyone; `git push --no-verify` remains a
  conscious, visible bypass.
- **Claude Code `PreToolUse` hook** — in the project's `.claude/settings.json`,
  matching `Bash(git push*)`, to gate pushes made *through Claude*.

Run `/pre-push-review` and it will offer to set one up.

## Layout

```
nj-agents/
├── skills/<name>/SKILL.md      # each skill is a directory + SKILL.md
├── agents/<name>.md            # each agent is a flat .md
├── CONVENTIONS.md              # shared rules for the review class
├── CONVENTIONS-authoring.md    # shared rules for the authoring class
├── install.sh                  # symlinks skills/ + agents/ into a .claude/ dir
└── README.md
```

## Adding more

Drop a new skill directory under `skills/` (with a `SKILL.md`) or a new agent `.md`
under `agents/`, then re-run `./install.sh`. Keep everything **project-agnostic** —
discover per-repo details at runtime rather than hardcoding a stack, path, port, or
tool. Point each new skill at the right class contract: `CONVENTIONS.md` if it only
reads and advises, `CONVENTIONS-authoring.md` if it writes an artifact into the repo.
