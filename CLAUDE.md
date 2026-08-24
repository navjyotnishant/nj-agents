# CLAUDE.md — nj-agents

Project guidance for Claude Code sessions working in this repo. Read this first.

## What this repo is

`nj-agents` is a personal, **project-agnostic** collection of Claude Code **skills and
agents** for software-development workflows. Install it once (symlinks into `~/.claude/`)
and invoke the skills with `/name` in **any** git repo — nothing here is specific to one
project, stack, or language.

- **38 skills · 29 agents**, in six classes + a diagram-generation subsystem.
- Install: `./install.sh` (global, Claude Code), `./install.sh --runner gemini|codex|cursor|agents`
  for another agent, or `--project DIR` for one repo. Everything is a **symlink back into
  this clone**, so installing for several runners leaves them all reading the same files —
  nothing to sync. The installer **globs**
  `skills/*/` and `agents/*.md`, so new files are picked up automatically. Reload Claude
  Code after installing (skills/agents load at session start).

## Repository structure (follow this exactly for new work)

```
skills/<name>/SKILL.md      # a skill is a DIRECTORY containing SKILL.md
skills/<name>/scripts/      # optional bundled helper scripts (node_modules is gitignored)
agents/<name>.md            # an agent is a FLAT .md file
CONVENTIONS.md              # review-class shared rules
CONVENTIONS-authoring.md    # authoring-class shared rules (§A1–A8)
CONVENTIONS-pm.md           # PM-authoring-class shared rules (§P1–P8); skills in NAV-82..84
CONVENTIONS-testing.md      # testing-class shared rules (§T1–T14); skills in NAV-161
CONVENTIONS-orchestration.md # §U binds EVERY skill; §C cost + §R progress for spawning ones
global/AGENTS.md            # advisory guidance → symlinked per runner (see install.sh)
install.sh                  # symlink installer (idempotent; safe uninstall; never clobbers)
check.sh                    # validator — frontmatter, refs, class contracts, cost/progress,
                             #   trigger-routing (scripts/gen-trigger-cases.sh), script self-tests,
                             #   artifact security scan (install lures, undeclared network calls)
bin/nj-agents-review        # headless /pre-push-review → §5 exit codes (0 PASS/WARN, 1 BLOCK, 2 error)
bin/nj-run                  # testing-class run harness — manifest §T13, cost §T10, subagents §T11, log §T12
tests/test-nj-run.sh        # its behavioural checks (no LLM, free, CI-safe)
README.md                   # public overview
mkdocs.yml                  # the reference SITE config (Material + gen-files + literate-nav)
docs_src/gen_pages.py       # generates every doc page into mkdocs' VIRTUAL tree at build time
docs/architecture/          # diagrams (embedded into the site) + their JSON source models
```

**The reference site is generated, never hand-written.** `docs_src/gen_pages.py` derives
one page per skill/agent/orchestrator — plus the tree nav (`SUMMARY.md`) and the
skill↔agent wiring — from `skills/*/SKILL.md` and `agents/*.md` at build time. Nothing
generated lands on disk, so a page **cannot** drift from the file it documents; add a
skill and its page appears with no registration step. Build it locally with:

```bash
python3 -m venv .venv-docs && ./.venv-docs/bin/pip install -r requirements-docs.txt
./.venv-docs/bin/mkdocs serve            # then open http://127.0.0.1:8000/nj-agents/
./.venv-docs/bin/mkdocs build --strict   # what CI gates on
```

**Open the served URL, never `site/index.html`.** Material generates *directory* URLs
(`href="skills/pm-plan/"`), which a browser cannot resolve over `file://` — every link
lands on a directory instead of its `index.html`, so the page renders as unstyled HTML
and looks broken. The build is fine; the viewing method is not. Mind the **`/nj-agents/`
prefix** too: `site_url` carries that subpath for GitHub Pages, so the dev server 302s
`/` → `/nj-agents/`. Published site: <https://navjyotnishant.github.io/nj-agents/>.

A class present in `skills/` but missing from `gen_pages.py`'s `CLASSES` map silently
produces **no page** — invisible until something links to it and `--strict` fails on the
dangling link. Add the class when you add the class.

- **Skill frontmatter:** `name`, `description` (trigger-phrase style, "Use this skill
  when the user asks to…", states it works in any repo), `version`, `class`
  (`review|authoring|workflow|pm|social` — what `check.sh` keys its class-conditional
  rules off; the prose class marker in the intro stays, for humans), `author`
  (from `git config user.name` at creation — never hardcoded; skills install as
  symlinks, so at the point of use the file is the only record of provenance).
  Review-class skills additionally declare `subclass`: **`gate`** reviews a *diff*
  and returns PASS/WARN/BLOCK (a hook can act on it), **`scan`** sweeps the *whole
  repo* for accumulated debt and returns candidates — there is no sensible BLOCK for
  "you have 12 unused exports". `check.sh` holds only gates to the verdict tokens.
- **Agent frontmatter:** `name`, `description` (may embed `<example>`/`<commentary>`),
  `tools`, `color`, `author`; optional `memory: project`. **Omitting `model:` inherits
  the session's model** — so an Opus session gets Opus subagents. Do not pin a model
  unless there is a specific, stated reason: a hardcoded tier silently overrides the
  user's own choice.
  **`tools:` is required, for portability rather than taste.** Claude Code and Cursor
  read a missing key as inherit-all, but **Gemini CLI reads it as _no_ tools** — the
  agent loads and then cannot act. An explicit allowlist is the only spelling that
  means the same thing on every runner. Most agents need only `Read, Grep, Glob`
  (+ `Bash` if they run commands): **23 of the 25 return content for the *skill* to
  write**, and their bodies say so. Only an agent that genuinely produces a file
  itself gets `Write` — today exactly two do, `screenshot-capturer` and
  `screenshot-redactor`. `diagram-architect` looks like a third and is not: it
  emits SVG *content* and the skill writes the file, which its body states
  outright ("Do not write files").
  `check.sh` fails an agent whose body claims read-only while its `tools:` declares
  a write tool.
- **kebab-case** names throughout. This layout matches the official Anthropic plugin
  convention (skill = dir + SKILL.md, agent = flat .md, `scripts/`/`references/` subdirs).

## The skill classes (pick the right shared rules)

- **Review class** — *advise only, leave no files, never commit.* Reads changes, reports.
  Shared rules: `CONVENTIONS.md`.
  Skills: `/pre-push-review` (umbrella) + `/review-secrets`, `/review-correctness`,
  `/review-tests-build`, `/review-dependencies`, `/review-style`.
  **Repo-maintenance** sub-group (review-class too — debt scans, not pass/fail gates;
  changed-set by default, `--full` for the whole tree):
  `/dead-code-finder`, `/test-gap-finder`, `/deps-upgrade`. Same advise-only discipline
  (never delete, never write tests, never upgrade); detect the repo's own tooling at
  runtime with a labeled fallback. `/deps-upgrade` surveys the whole manifest for
  *available* upgrades — distinct from `/review-dependencies`, which reviews diff changes.
- **Authoring class** — *writes an artifact into the repo, then PROPOSES the commit.*
  **Never `git add`/`commit`/`push`/`tag` automatically.** Shared rules:
  `CONVENTIONS-authoring.md` (§A1 repo-ingest, §A2 scoped output, §A3 propose-commit,
  §A4 placement, §A5 MCP-detect-never-require, §A6 grounding/safety, §A7 idempotent,
  §A8 degrade-when-denied).
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
  §P6 MCP-detect-never-require, §P7 safety, §P8 report-the-tree). Leaf skills `/pm-epic`, `/pm-story`,
  `/pm-task` + the `/pm-plan` orchestrator (decomposes via `pm-decomposer`, previews the
  whole tree, then creates it sequentially parent-first with stop-on-partial-failure).
  Motivated by the global "track work in a PM tool" rule.
- **Social class** — produces paste-ready copy; never writes to the repo, never auto-posts.
  Skill: `/social-post`.
- **Testing class** — *writes test source into the repo **and executes it** against a
  running app.* The only class that does either, which is why it is its own class
  rather than a squeeze into authoring: `/review-tests-build` runs commands but writes
  nothing, `/test-gap-finder` explicitly never writes tests. Shared rules: `CONVENTIONS-testing.md` (§T1–T14). Three of those are enforced by `check.sh`:
  **T1** writes only inside detected test directories, never app source · **T2** never
  weakens or deletes an assertion, and no sleeps/retries/skips to force green ·
  **T3** requires an explicit non-prod base URL, else BLOCK. A read-only testing
  skill opts out of T1 by stating it is read-only, never by omission.
  All ten skills exist; two are umbrellas — `/test-suite-author` generates,
  `/e2e-suite` executes.

  **Run state goes through `bin/nj-run`, not through per-skill JSON.** It owns the
  §T13 manifest, §T10 cost accounting, §T11 subagent spawn/join, and the §T12
  append-only log. One tool rather than ten because §T13's whole point is that an
  umbrella can only report cost and subagent records uniformly if they are *recorded*
  uniformly — ten skills each writing "the same" schema is how that stops being true,
  and a cost baseline computed by two different code paths compares the code, not the
  runs. It is detected-never-required like everything else (§A5): absent, a skill
  hand-writes the §T13 fields and says the cost and log fields are missing.
  Two properties are easy to lose in a hand-rolled reduce and are why `nj-run
  aggregate` exists: a quarantined subagent **forces BLOCK** rather than being
  outvoted by the dimensions that did complete, and no-dimensions-or-all-SKIP is a
  **PASS** (§U) rather than an ambiguous exit 2 that blocks a push for no reason.
  `tests/test-nj-run.sh` asserts both, plus the §T4 scrub on published log text;
  `check_run_harness` fails the build if those checks stop passing.

> The one rule both code-facing classes share: **the human decides what gets committed.**
> (The user may explicitly say "commit and push" — then it's fine.)

**Any skill that spawns subagents** — whatever its class — also follows
`CONVENTIONS-orchestration.md`: **§C** state the cost shape before dispatch, cap fix
rounds at 2, halt on any signal to stop; **§R** announce the agent roster before
dispatch and mark each one as it lands. `check.sh` detects spawning from the skill's
own text, so a new skill is bound the moment it says "spawn".

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

Diagrams are **authored directly as SVG**, not emitted from a renderer. That is what
allows gradients, hexagons, legends and a takeaway row, and what lets a layout be
*rearranged* when it reads badly rather than being stuck with a grid's output.

- **Two styles, same layout.** `infographic` is the **default** — clean gradients,
  system font, crisp connectors. `--sketch` swaps in flat paper fills, a handwriting
  font and a subtle wobble on card borders. Only the finish differs, so switching
  never invalidates a layout that already passed review.
- **Enforced visual gate (do not skip):** render the SVG to PNG (`rsvg-convert`),
  **look at it**, and critique it against the 15-second test — does the headline state
  the outcome, do any arrows cross, is any text clipped, is every number right? Fix
  and repeat, capped at 2 rounds. Source review cannot catch a label hidden behind a
  frame stroke or an arrowhead eaten by a filter; only rendering it can.
- **Semantic colour is absolute:** red = failure/block/stop, green = success/pass,
  orange = AI agents, grey = neutral input. Never green a failure or red a success.
  Hexagons are agents; rounded rectangles are stages. Only use a shape that has
  something to represent on that diagram.
- **Sketch gotcha:** a displacement filter on a `<path>` suppresses its arrowheads —
  SVG markers are not rendered through a filter. Wobble the cards, never the
  connectors.

The previous rough.js renderer (`icon_diagram.js` / `flow_diagram.js` /
`qa_diagram.js`) and the `diagram-qa` agent were removed in v0.4.0. The four diagrams
it produced remain as committed SVGs and are now edited by hand.

## Editing gotchas

- **Never hand-edit a generated doc page.** The site is rebuilt from `skills/`/`agents/`
  on every build, so an edit to a rendered page is overwritten and silently lost. Change
  the SKILL.md/agent file, or `docs_src/gen_pages.py` if the *shape* of the page is wrong.
- **Gitignored (local only):** `node_modules/`, `docs/architecture/*.layout.json`,
  `HANDOFF*.md`, `_style-mockups.html`, `.nj-agents-reports/`, `.DS_Store`.
- A local, gitignored **`HANDOFF.md`** holds deeper working notes (build history,
  environment specifics, the EM-suite backlog, parked items). If present, read it for
  richer context; it is not shared via git.

## Branches

- **`main`** — the integration branch. Feature work merges here; CI runs on every
  push and PR.
- **`PRD`** — what gets released and installed from. Promoted from `main` via a PR
  once CI is green and the change has been used for real.

```bash
gh pr create --draft --base PRD --head main --title "…" --body-file …
gh pr merge <n> --merge          # after CI is green and you've marked it ready
```

Promotion goes through a PR, not a local merge: `PRD` is protected, so a direct
push is rejected and `git merge --ff-only` has nowhere to land. That leaves a merge
commit on `PRD` — accepted deliberately. The guarantee that matters is *`PRD` never
contains a commit that was not first on `main` and green*, and the required PR plus
the `check` status enforce that on the server. A linear history would additionally
need force-push, which protection blocks by design.

Use `/pr-describe` to draft the promotion PR — it grounds the body in the real
`PRD..main` delta rather than a hand-written commit list.

**`PRD` is protected server-side.** A PR is required, the `check` status check must
pass, and force-push and deletion are blocked. `enforce_admins=false` and
`required_approving_review_count=0` keep self-merge possible for a solo maintainer —
which also means the owner can override the gate, so it is a guard rail rather than a
wall. `main` is deliberately unprotected: it is where work integrates.

`./install.sh --git-hooks` additionally installs a local `pre-push` hook running the
same checks, so problems surface before a push rather than after.

## Commit style

- Conventional commits (`feat:`, `fix:`, `docs:`, `chore:`, `style:`). No `Co-Authored-By`.
- Authoring skills **propose** commits; a human (or an explicit "commit and push")
  decides. When you do commit, review `git status` first — only intended files.

## Adding a new skill/agent

**Scaffold it — don't hand-write the frontmatter.** The template is correct by
construction and the validator tells you what is still missing:

```bash
./check.sh --new-skill <name> --class review|authoring|workflow|pm|social
./check.sh --new-agent <name>
```

1. Fill the ALL-CAPS placeholders and every section marked REQUIRED for the class.
   A review skill must also pick `subclass: gate` (reviews a diff, returns
   PASS/WARN/BLOCK) or `subclass: scan` (sweeps the repo, returns candidates).
2. If it spawns agents, uncomment the `CONVENTIONS-orchestration.md` block and
   replace `COST_SHAPE` with the real fleet. Leaving it commented is deliberate —
   `check.sh` reports the gap rather than passing on placeholder text.
3. `./install.sh` → reload Claude Code.
4. **`./check.sh` must be clean.** It globs, so the new file is covered immediately.
5. Add a `CHANGELOG.md` entry under `[Unreleased]` — a new skill is user-facing.
   Use `/changelog`; see the standing rule in `global/AGENTS.md`.
6. Update `README.md` and the right table in **`global/AGENTS.md`** — those are
   hand-maintained, and AGENTS.md is what makes the skill discoverable in *other*
   repos. `check.sh` flags it if you forget. The **reference site needs no edit**: it
   globs `skills/`/`agents/` and picks the new one up on the next build.
7. **If the skill bundles a `scripts/` dir with executable code, add a
   `test_*.py` alongside it** (stdlib `unittest`, tempdir fixtures, no network —
   see `skills/tech-blog/scripts/test_*.py` for the pattern: import the target
   script via `importlib.util`, test its pure/deterministic functions, skip
   anything that shells out or hits a real API). `check_script_self_tests`
   flags a `scripts/` dir with `.py` files but no matching `test_*.py`.
8. **If a `scripts/*.py` file makes a network call, name it in the skill's own
   `## Dependencies` table** — `check_artifact_security` flags an undeclared one.
   A `curl`/`wget` piped straight into a shell is never legitimate inside a
   script and always fails the check, declared or not; the same pattern in a
   `SKILL.md`/`agents/*.md` install instruction is fine as long as it's framed
   for a human to run themselves (e.g. "do not install anything yourself" —
   see `review-secrets/SKILL.md`'s scanner-install block for the pattern).

`templates/` holds the sources; they are not skills themselves and are not globbed.
