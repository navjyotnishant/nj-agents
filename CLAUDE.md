# CLAUDE.md — nj-agents

Project guidance for Claude Code sessions working in this repo. Read this first.

## What this repo is

`nj-agents` is a personal, **project-agnostic** collection of Claude Code **skills and
agents** for software-development workflows. Install it once (symlinks into `~/.claude/`)
and invoke the skills with `/name` in **any** git repo — nothing here is specific to one
project, stack, or language.

- **20 skills · 23 agents**, in four classes + a diagram-generation subsystem.
- Install: `./install.sh` (global) or `./install.sh --project DIR`. The installer **globs**
  `skills/*/` and `agents/*.md`, so new files are picked up automatically. Reload Claude
  Code after installing (skills/agents load at session start).

## Repository structure (follow this exactly for new work)

```
skills/<name>/SKILL.md      # a skill is a DIRECTORY containing SKILL.md
skills/<name>/scripts/      # optional bundled helper scripts (node_modules is gitignored)
agents/<name>.md            # an agent is a FLAT .md file
CONVENTIONS.md              # review-class shared rules
CONVENTIONS-authoring.md    # authoring-class shared rules (§A1–A8)
CONVENTIONS-pm.md           # PM-authoring-class shared rules (§P1–P7); skills in NAV-82..84
global/CLAUDE.md            # advisory guidance → symlinked to ~/.claude/CLAUDE.md
install.sh                  # symlink installer (idempotent; safe uninstall; never clobbers)
README.md                   # public overview
docs.html                  # multi-page reference SITE (Home/Suites/Workflows/Reference)
docs/architecture/          # generated diagrams + their JSON source models
```

- **Skill frontmatter:** `name`, `description` (trigger-phrase style, "Use this skill
  when the user asks to…", states it works in any repo), `version`.
- **Agent frontmatter:** `name`, `description` (may embed `<example>`/`<commentary>`),
  `model`, `color`; optional `memory: project`. Omitting `tools:` inherits all tools.
- **kebab-case** names throughout. This layout matches the official Anthropic plugin
  convention (skill = dir + SKILL.md, agent = flat .md, `scripts/`/`references/` subdirs).

## The skill classes (pick the right shared rules)

- **Review class** — *advise only, leave no files, never commit.* Reads changes, reports.
  Shared rules: `CONVENTIONS.md`.
  Skills: `/pre-push-review` (umbrella) + `/review-secrets`, `/review-correctness`,
  `/review-tests-build`, `/review-dependencies`, `/review-style`.
- **Authoring class** — *writes an artifact into the repo, then PROPOSES the commit.*
  **Never `git add`/`commit`/`push`/`tag` automatically.** Shared rules:
  `CONVENTIONS-authoring.md` (§A1 repo-ingest, §A2 scoped output, §A3 propose-commit,
  §A4 placement, §A5 MCP-detect-never-require, §A6 grounding/safety, §A7 idempotent).
  Skills: `/changelog`, `/arch-diagram`, `/capture-screenshots`, `/tech-blog`, `/docs-site`,
  `/scaffold-project`. The last is the one authoring skill that runs on a **greenfield**
  repo — with no repo to read, §A6 is satisfied by grounding in the **OpenSSF OSPS
  Baseline** (cited by control ID) + the ecosystem's own generator + a supplied project
  doc, never by inventing.
- **Workflow class** — *reads the diff, drafts a change artifact, proposes — never auto-acts.*
  Sits between review and authoring: reads a diff like review-class but invents nothing,
  proposes like authoring-class (§A3) but its artifact is a **PR, not a repo file** (so
  the §A2/§A4 placement rules don't apply). `gh` detected-never-required (§A5).
  Skills: `/pr-describe`, `/commit-assistant`, `/release-notes`. `/commit-assistant`
  sits directly on the "human decides what gets committed" rule — its whole output
  **is** the §A3 commit block, so it drafts message(s) and prints `git add`/`commit`,
  but never runs git. `/release-notes` **composes with `/changelog`** rather than
  duplicating it: `/changelog` writes the `CHANGELOG.md` file, `/release-notes` reuses
  that section to draft the GitHub **Release** object — draft only, never publishes,
  never pushes a tag.
- **PM-authoring class** — *writes a work item into a project-management tracker
  (Linear/Jira/Notion/GitHub Issues), then PROPOSES the create.* The artifact is a
  **tracker object, not a repo file**, so the §A2/§A4 placement rules don't apply.
  Shared rules: `CONVENTIONS-pm.md` (§P1 ground, §P2 neutral-model→per-tracker map,
  §P3 propose-the-create, §P4 tracker idempotence, §P5 sequential parent-first,
  §P6 MCP-detect-never-require, §P7 safety). Leaf skills `/pm-epic`, `/pm-story`,
  `/pm-task` + the `/pm-plan` orchestrator (decomposes via `pm-decomposer`, previews the
  whole tree, then creates it sequentially parent-first with stop-on-partial-failure).
  Motivated by the global "track work in a PM tool" rule.
- **Social class** — produces paste-ready copy; never writes to the repo, never auto-posts.
  Skill: `/social-post`.

> The one rule both code-facing classes share: **the human decides what gets committed.**
> (The user may explicitly say "commit and push" — then it's fine.)

## Core conventions

- **New authoring skill?** Reference `CONVENTIONS-authoring.md`; put bundled tooling in a
  `scripts/` subdir; gitignore any `node_modules`.
- **Ground everything** — skills read the *actual* repo (README/docs/code) and never
  invent APIs, files, or facts (`CONVENTIONS-authoring.md §A6`). `/tech-blog`'s
  fact-checker and `/docs-site`'s gap-flagging enforce this.
- **Degrade, don't fail** — external tools/MCPs are **detected at runtime, never
  required** (§A5); every skill has a zero-dependency fallback.
- **Secret scanning is mandatory** — `/review-secrets` (and the `/pre-push-review` gate)
  require a real scanner (`gitleaks`/`trufflehog`/`detect-secrets`) and BLOCK if none is
  installed. `gitleaks` is installed on the primary dev machine.

## Diagram subsystem (`/arch-diagram`) — read before touching diagrams

The house style is **icon tiles** (crisp line icon + label + class-color stripe) with a
subtle Excalidraw sketch texture (rough.js) and a hand-drawn black frame. It is
generated from a small JSON model, not hand-placed.

- Renderers + QA in `skills/arch-diagram/scripts/`: `icon_diagram.js` (lane/tile),
  `flow_diagram.js` (process flows), `qa_diagram.js` (deterministic checker),
  `diagram_common.js` (shared palette + icon set + **semantic-color contract**).
  Run `npm install` in that dir once (rough.js; `node_modules` gitignored).
- **Enforced visual-QA loop (do not skip):** after every render, spawn the **`diagram-qa`**
  agent → it runs `qa_diagram.js` + a visual PNG pass → returns a **BLOCKING** verdict.
  Loop render → QA → fix until PASS. Mechanical issues (overflow/clip/missing-icon) the
  renderer auto-fixes; layout/color issues go back to `diagram-architect`.
- **Semantic color is enforced:** red = failure/block/stop, green = success/pass/output,
  class color = ordinary steps, grey = neutral inputs. Never green a failure or red a
  success (`diagram_common.js` documents it; `qa_diagram.js` flags violations).
- SVG→PNG for the visual pass: `rsvg-convert` (ships with graphviz/cairo).

## Editing gotchas

- **`docs.html` is one large file — edit surgically.** When swapping an embedded SVG,
  do a *per-block regex replace* of just the `<svg>…</svg>`, never an index-based splice
  (an index splice once duplicated whole pages).
- **Gitignored (local only):** `node_modules/`, `docs/architecture/*.layout.json`,
  `HANDOFF*.md`, `_style-mockups.html`, `.nj-agents-reports/`, `.DS_Store`.
- A local, gitignored **`HANDOFF.md`** holds deeper working notes (build history,
  environment specifics, the EM-suite backlog, parked items). If present, read it for
  richer context; it is not shared via git.

## Commit style

- Conventional commits (`feat:`, `fix:`, `docs:`, `chore:`, `style:`). No `Co-Authored-By`.
- Authoring skills **propose** commits; a human (or an explicit "commit and push")
  decides. When you do commit, review `git status` first — only intended files.

## Adding a new skill/agent

1. Skill → `skills/<name>/SKILL.md` (+ `scripts/` if needed); agent → `agents/<name>.md`.
2. Use the frontmatter format above; reference the right conventions doc by class.
3. `./install.sh` (globs automatically) → reload Claude Code.
4. Update `README.md`'s tables and, if it's user-facing, `docs.html`.
5. Add it to the right table in **`global/CLAUDE.md`** — that file is what makes the
   skill discoverable in *other* repos, and it lists skills explicitly (no glob).
   `./install.sh` (or `--check-only`) warns if you forget; the warning is advisory
   and never fails the install.
