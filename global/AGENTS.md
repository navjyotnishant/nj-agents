# Global guidance — nj-agents SDLC toolkit

<!--
  Source of truth: <nj-agents repo>/global/AGENTS.md
  Installed as a SYMLINK by nj-agents/install.sh, under whichever filename the
  runner reads — ~/.claude/CLAUDE.md, ~/.codex/AGENTS.md, ~/.gemini/GEMINI.md.
  All of them point back HERE, so there is one copy and nothing to keep in sync.
  Edit it in the repo, not through a link. Repo: github.com/navjyotnishant/nj-agents
-->

A personal toolkit of Claude Code **skills and agents** covering the software
development lifecycle is installed globally on this machine — **37 skills, 27
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
| `/pre-push-review` | **Umbrella.** Secret scan as a gate, then the rest in parallel; aggregates one PASS / WARN / BLOCK verdict, then renders an HTML report and prints its `file://` URL. | orchestrates the below + `review-report-writer` |
| `/review-secrets` | Scanner over the diff **first** as a hard gate, then a semantic security pass. | `secrets-reviewer` |
| `/review-correctness` | Bugs, regressions, edge cases, missing validation in changed lines + blast radius. | `correctness-reviewer` |
| `/review-tests-build` | Auto-detects and runs the repo's own test/lint/build commands. Never installs tooling. | `tests-build-runner` |
| `/review-dependencies` | Added/upgraded packages, pinning risk, license changes, typosquatting. Diff-only. | `dependency-reviewer` |
| `/review-style` | Consistency with surrounding code, commit-message hygiene, leftover debug/TODO. | `style-reviewer` |
| `/claude-design-pull` | Pulls approved mockups from Claude Design and **BLOCKS** while a page's structure or computed styles differ. Measures only; never edits app code. | `design-parity-checker` |

Each runs standalone; the umbrella runs them together. Shared behavior lives in the
repo's `CONVENTIONS.md`.

**Secret scanning is a hard requirement.** `/review-secrets` and the umbrella need
`gitleaks`, `trufflehog`, or `detect-secrets` on PATH and **BLOCK with install
instructions** if none is present — there is no heuristic-only fallback. On a hit the
review **stops and shares nothing**. (`gitleaks` is installed on this machine.)

**Repo-maintenance** (review-class too — advise only, never modify): maintenance-debt
scans rather than pass/fail gates. Like the gates they **default to your changed set**
and take `--full` for the whole tree — except `/deps-upgrade`, whose subject is the
whole manifest by definition.

| Skill | What it does | Agent |
|---|---|---|
| `/dead-code-finder` | Finds unreferenced code (unused exports/functions/files/deps); detects the repo's own tool (knip/ts-prune, vulture, deadcode, cargo-udeps) or falls back to a manual cross-reference. Confidence-rated; **never deletes**. | `dead-code-finder` |
| `/test-gap-finder` | Maps code paths to tests, flags uncovered paths + missing edge-case tests; uses the repo's own coverage tool, else a labeled heuristic. **Never writes tests.** | `test-gap-finder` |
| `/deps-upgrade` | Surveys the **whole manifest** for available upgrades (distinct from `/review-dependencies`, which reviews diff changes); risk-classifies and proposes a plan. Zero-network by default; **never upgrades or edits the manifest**. | `deps-upgrade` |

## Authoring suite — writes one artifact, then PROPOSES the commit

| Skill | What it does | Agents |
|---|---|---|
| `/changelog` | `CHANGELOG.md` in Keep a Changelog + SemVer from commit history. Merges into `[Unreleased]` without clobbering; suggests the bump. (For the GitHub **Release** object, see `/release-notes`.) | `changelog-writer` |
| `/arch-diagram` | Authors a presentation-quality SVG into `docs/architecture/` — infographic by default, `--sketch` on request. Renders and reviews it before shipping. | `diagram-architect` |
| `/capture-screenshots` | Capture → detect PII/secrets → blur/mask → **verify coverage before writing**. | `screenshot-capturer`, `sensitive-data-reviewer`, `screenshot-redactor` |
| `/screenshot-docs-sync` | Keeps docs and their embedded screenshots current as the UI drifts — diffs since the last doc update, re-captures only what changed, edits in place. The *maintenance* loop; `/capture-screenshots` is the one-shot. | (no dedicated agent) |
| `/docs-site` | Self-contained theme-aware `docs.html` from docs, code, an outline, or SKILL.md/OpenAPI/JSON-Schema. Auto-derives the menu; flags gaps rather than inventing. | `docs-architect`, `docs-designer` |
| `/tech-blog` | writer → fact-checker → reviewer → editor → final-polish → platform-lint → optional poster. Generates its own diagrams/screenshots, then embeds them. | `blog-writer`, `blog-fact-checker`, `blog-reviewer`, `blog-editor`, `blog-final-polish`, `blog-platform-lint`, `blog-poster` |
| `/scaffold-project` | Lay out a **new** repo to the OpenSSF OSPS Baseline (Level 1 default), delegating stack layout to the ecosystem generator (`cargo new`/`uv init`/…). Cites each file by control ID; verifies before reporting done. | (no dedicated agent) |
| `/social-post` | LinkedIn / X copy for a **published** URL — short / medium / builder-story, hook-first, clean hashtags. Never writes to the repo, never auto-posts. | `social-post` |

Shared behavior lives in the repo's `CONVENTIONS-authoring.md` (§A1 repo-ingest,
§A2 scoped output, §A3 propose-commit, §A4 placement, §A5 MCP-detect-never-require,
§A6 grounding/safety, §A7 idempotent, §A8 degrade-when-denied).

Two gates worth knowing: `/tech-blog`'s **fact-checker BLOCKS** on any claim it
can't verify against the repo, and `/arch-diagram` runs a mandatory
**render → look → critique** loop until the diagram reads in 15 seconds.

## Workflow suite — reads the diff, drafts a change artifact, proposes (never auto-acts)

| Skill | What it does | Agent |
|---|---|---|
| `/pr-describe` | Drafts a PR **title + body** from the branch's delta vs its base (the PR view). Fills the repo's own PR template when present; grounds every line in a real commit/hunk. Opens a **draft** PR only if you opt in and `gh` is present; else hands you the text. **Never pushes, never opens a non-draft PR, never merges.** | `pr-describer` |
| `/commit-assistant` | Drafts Conventional Commits message(s) from the working-tree changes and prints the `git add` + `git commit` block. Splits unrelated changes into separate commits; respects existing staging. Then **offers to run each one**, asking per commit and showing exactly what it would stage. **Never pushes or tags**; CI mode prints only. | (no dedicated agent) |
| `/release-notes` | Turns a version's changes into a **draft GitHub Release** — reuses the `CHANGELOG.md` section as the body (composes with `/changelog`), else summarizes the commit delta. Drafts `gh release create --draft`; **never publishes, never pushes a tag.** | (no dedicated agent) |

Reads a diff like the review class but invents nothing; proposes like the authoring
class (§A3) but its artifact is a **PR, not a repo file** — so it never writes to
`docs/`. `gh` is detected, never required (§A5).

## EM intelligence suite — self-contained weekly briefings (runs anywhere)

Two **self-contained** skills (`self_contained: true`) that carry their whole method
inline — research → adversarial verification → synthesis → render — so they run on any
agentic platform with code execution + web search, not just this toolkit. Every claim
is corroborated or visibly quarantined; nothing is invented.

| Skill | What it does | Agent |
|---|---|---|
| `/em-newsletter` | Weekly account-intelligence report for an Engagement Manager — book of accounts, market pulse, leadership moves, competitive landscape. Full setup path + account deep-dive. | (self-contained) |
| `/vertical-pulse` | One-line shortcut into the same pipeline — `/vertical-pulse <Vertical>` resolves accounts/tech from saved config or a short prompt, defaults to the cheap verification mode. | (self-contained) |

## PM-authoring suite — writes a work item into a tracker, PROPOSES the create

Tool-agnostic (Linear / Jira / Notion / GitHub Issues via a connected MCP), draft-first,
MCP-detect-never-require, with a paste-ready-markdown fallback. Shared rules in
`CONVENTIONS-pm.md`. This is what the "track work in a PM tool" standing rule uses to
create the tracked item. **Every item is drafted to a recognized standard** — INVEST
(stories), the Scrum Guide (Gherkin acceptance criteria, Definition of Done), and SAFe
(Epic→Story→Task hierarchy, epic hypothesis); `CONVENTIONS-pm.md §P0` pins the complete
field set per type.

| Skill | What it does | Agent |
|---|---|---|
| `/pm-epic` | Drafts one **Epic** to the **SAFe epic-hypothesis** standard (goal/outcome, problem, success measure, scope/out-of-scope) + a **suggested** story breakdown; on opt-in creates the epic only. Use `/pm-plan` to build the whole tree. | (no dedicated agent) |
| `/pm-story` | Drafts one **INVEST user story** ("As a … I want … so that …") + **Gherkin (Given/When/Then) acceptance criteria** per the Scrum Guide; on opt-in creates it in the connected tracker, else paste-ready markdown. Optional parent Epic. | (no dedicated agent) |
| `/pm-task` | Drafts one scoped, actionable **Task** with an explicit **done-when (Scrum Definition of Done)** exit condition (optionally under a Story/Epic); on opt-in creates it, else markdown. | (no dedicated agent) |
| `/pm-plan` | **Orchestrator.** Decomposes a feature-sized ask into an Epic→Stories→Tasks tree (via `pm-decomposer`), previews the **whole tree** for one approval, then creates it **sequentially, parent-first**, wiring links. Stops-and-reports on any partial failure; reconciles a re-run so it never double-creates. | `pm-decomposer` |

## Testing suite — writes test source AND executes it

The only class that does both, which is why it has its own contract
(`CONVENTIONS-testing.md`, §T1–T14) rather than sitting under authoring. Three
clauses are enforced by `check.sh`, not merely stated: **T1** writes only inside
detected test directories, **T2** never weakens or deletes an assertion, **T3**
requires an explicit non-prod base URL or it BLOCKs.

| Skill | What it does | Agent |
|---|---|---|
| `/e2e-suite` | **Umbrella.** Runs the suite, classifies every failure, returns one PASS/WARN/BLOCK. Cost scales with *failures*, not specs — a green suite is nearly free. **Never repairs anything**: a gate that fixes its own failures is not a gate. A test bug is WARN, never PASS (the app is fine, the suite is lying), and ambiguity never resolves toward PASS. | orchestrates the below |
| `/e2e-run` | Detects the repo's **own** E2E runner (Playwright/Cypress/WDIO/…), BLOCKs unless the base URL is explicitly non-prod, runs the suite, and captures trace/HAR/video/console into a **gitignored temp dir**. Raw artifacts never leave it; published text is secret-scrubbed. Runs tests, never writes them. | (none yet) |
| `/test-suite-author` | **Generation umbrella.** Ticket → cases → specs → fixtures in one run: chains `/test-plan` → `/test-author` → `/test-data`. **Pauses after every stage** so each is reviewed before the next consumes it; `--yes` skips the prompts for a workflow but removes no constraint. On approval, files the uncovered cases as `TEST-`-prefixed tracker sub-tasks via `/pm-task` (§P4 search-before-create, so a re-run links rather than duplicates). **Never commits** — not with `--yes`, not in CI. | orchestrates the three below |
| `/test-plan` | Turns a requirement (from a connected tracker, or pasted) into a **structured case matrix** — equivalence classes, boundaries, negative paths, authz, not just the happy path. Consumes `/test-gap-finder`'s coverage rather than recomputing it, marks each case `new`/`covered`/`inferred`, and emits JSON for `/test-author`. Advises only. | (none yet) |
| `/test-author` | Generates specs from those cases **in the repo's own framework** — never one it picks. Enforces a `data-testid` locator contract and flags brittle selectors (`nth-child`, text matching, XPath). Writes only inside detected test dirs; if testids are missing it **proposes** adding them rather than reaching into app source. Proposes the commit. | (none yet) |
| `/test-data` | Fixtures and factories so **each spec owns its data** — unique per run, created by the spec, cleaned up after. Shared mutable fixtures are the usual cause of "flaky" suites that pass alone and fail in parallel. Credentials from env, never written to disk (§T8). Proposes the commit. | (none yet) |
| `/test-repair` | Fixes a test **only where the test is at fault** — fires solely on `/test-triage`'s `test-bug` verdict; every other class BLOCKs, including `flake` (every repair for a flake is forbidden). May fix selectors, waits, setup, teardown. **May not weaken or delete an assertion, add a sleep, raise a retry, or add a skip** — assertion changes escalate rather than appearing in the diff. If the real fix is in app source it says so and stops. Proposes a diff; never commits. | (none yet) |
| `/test-report` | Traceability: requirement → case → spec → status → defect, plus the release position. **Leads with what is NOT covered** — a report that lists passes reads as "we tested this", and a pass rate is not coverage. Weights passes by flake history: a green run resting on three known-flaky specs is not the same result. States the position; does not make the call. | (none yet) |
| `/flake-watch` | Reads the **committed** flake ledger: fail rate per spec over the last N runs, what is trending worse, what crosses the quarantine threshold. Quarantine is **proposed, never applied** — each with an SLA and a tracking issue, because a spec dropped from the gate with no owner is a spec deleted slowly. Reports "insufficient history" rather than a rate from three runs, and routes a 100%-failing spec to `/test-triage` (that is a defect, not a flake). | (none yet) |
| `/test-triage` | Explains a red build: classifies each failure as **real defect · test bug · environment · flake · data**, with a confidence and cited evidence, and blames suspect commits. Reads `/e2e-run`'s manifest, the diff since last green, and the flake ledger. **Never calls `flake` from a single run** — that needs ledger history, or a real race condition gets ignored for a quarter. Advises only; hands defects to `/pm-task` on your say-so. | (none yet) |

**Two rules worth knowing before using this class.** Raw artifacts stay local — a
trace is never attached to a ticket, and an export attempt BLOCKs with the local
viewer command instead. But text *derived* from an artifact and published into a
report or ticket is scrubbed first, because a bearer token in a query string leaves
through a report with no artifact ever moving.

All ten skills in the class now exist — two umbrellas: `/test-suite-author` generates, `/e2e-suite` executes. Agents (`e2e-runner`, `failure-triager`,
`test-planner`, `test-repairer`) are tracked under NAV-161.

## Cost and loop control (applies to every skill and agent)

Skills in this toolkit spawn subagents, and subagents cost real money. Several
have render→QA→fix or find→verify loops that can run for many rounds. Treat
spend as a budget you must manage, not an implementation detail.

For the review suite specifically, these rules are made concrete in
`CONVENTIONS.md` **§8 Cost control** — scope-and-confirm before spawning, skip
dimensions with nothing to review, and re-run only the dimensions that still
have findings.

- **Say the cost shape before starting.** If a request will spawn subagents or
  run a multi-round loop, say so in one line and get a yes — *"this runs a
  render→QA loop, usually 2–4 agent calls"* — before firing it. Don't discover
  the cost mid-run.
- **Hard cap: 2 fix rounds.** After two failed QA/verify cycles on the same
  artifact, **stop and report**: what's fixed, what still fails, the options. Do
  not start a third round without being asked.
- **A blocking verdict is a checkpoint, not a to-do.** When a QA/review agent
  returns BLOCK, the default is to surface it — not to silently fix and re-run.
  Say what it found and what fixing it would cost.
- **Never chain skills unprompted.** "Do X and Y" authorizes X and Y, not the
  agents each of them might spawn in turn. Finish X, report, then confirm Y.
- **Cheap path first.** If a one-line flag, a manual edit, or plain prose gets
  90% of the value, do that and offer the skill as the upgrade. A skill is not
  automatically the right tool just because it matches the topic.
- **Stop on any signal to stop.** "This is taking a while", "that's expensive",
  a suggested change of approach, or an interrupt all mean **halt and check in**
  — not "acknowledge and continue".
- **Ship at good-enough.** An artifact that is correct and usable but missed a
  final polish pass should be delivered with the gap stated plainly, not
  perfected at 10× the cost.

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
- **On finishing a tracked item, report the whole tree — not just that item.** End
  the update with every sibling under the same parent: done ones first with `✅`, the
  rest in dependency/priority order, aligned columns (`key · short title · priority ·
  estimate`), `← new` on anything added this session. A bare "done ✅" says what
  happened but not where the user now is, so they have to go look it up. Pair the tree
  with the commit SHA and one line on anything surprising, and put the tree last.
  Full rule and example: `CONVENTIONS-pm.md §P8`.
- **Keep `CHANGELOG.md` current — don't reconstruct it later.** A repo with user-facing
  changes should have one, in Keep a Changelog format with an `[Unreleased]` section.
  Update it **when the work lands**, not at release time: a changelog written months
  later from `git log` is a commit list with better formatting, because the reasons
  are gone. Use `/changelog` rather than hand-writing entries — it merges into
  `[Unreleased]` without clobbering and drops `wip`/`fixup`/merge noise.
  **When to update it:** a feature, a fix, a breaking change, a deprecation, or
  anything a user of this repo would want to know. **When not to:** refactors, test
  changes, docs-only edits, internal tooling — those are in the git history and don't
  belong in a user-facing record.
  If a repo has no `CHANGELOG.md` and is accumulating real changes, **offer to start
  one** rather than silently letting the gap grow. A throwaway repo, or one with no
  users and no releases, doesn't need one — say so and move on rather than
  hard-blocking. A project whose own `CLAUDE.md` sets a different policy overrides
  this.
- **Author header on new scripts and standalone modules.** For a new script, migration,
  or major standalone module, add a comment header at the top:

  ```
  Author: <owner>
  Created: YYYY-MM-DD
  Last updated: YYYY-MM-DD
  Description: <one line>
  ```

  Fill `<owner>` from **`git config user.name`** at the time the file is created —
  don't hardcode a name. On this user's machine that resolves to their identity; on a
  teammate's machine it resolves to theirs, so the stamp stays correct without editing
  the rule. If `git config user.name` is unset, ask rather than guessing. **Skip trivial
  files** (tiny components, generated files, one-off throwaways). A project whose own
  `CLAUDE.md` defines a different header format or authorship policy (e.g. EngageHub's
  "actual owner — do not derive from git config") overrides this. **Skills and agents
  carry the same stamp** as an `author:` frontmatter key rather than a comment header
  — they install as symlinks and run from any repo, so at the point of use the file
  is the only record of where it came from.
- **Before shipping a feature, there should be a test.** Not a suite, not coverage —
  a test that would fail if the feature broke. Offer `/test-suite-author` (ticket →
  cases → specs → fixtures, pausing at each stage) or `/test-plan` alone when the
  question is only "what should we test?".
  **Detect-never-require:** no test framework, a throwaway repo, or the user
  declines → note it and proceed. Never hard-block work on a missing test. A project
  whose own `CLAUDE.md` mandates a stricter gate overrides this softer default.
  **The push gate is per-project and opt-in**, consistent with the rule below:
  `./install.sh --git-hooks --project DIR` installs `pre-push-e2e`, which runs the
  repo's own suite and blocks a red push. It **spends nothing** — no agent, no API
  call — and until `.nj-agents/e2e.conf` exists it exits 0 on every push and says it
  is not configured. The paid `/e2e-suite` triage belongs in CI once per PR
  (`bin/nj-agents-e2e`), never on push.
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
  The ready-made one is `hooks/git/pre-push-review`, installed with
  `./install.sh --review-gate --project DIR`. It fires **only when the push targets
  `main` / `master` / `PRD` / `release/*`** — the inner loop stays free, the branch
  that reaches production does not. `NJ_REVIEW_SKIP=1` bypasses (loudly),
  `NJ_REVIEW_AUTO=1` runs it unattended for a workflow. Deliberately *not* a merge
  hook: git skips `pre-merge-commit` on a fast-forward, and most merges to `main`
  are fast-forwards, so that gate would silently pass on the common case.

## Suggesting a skill

Good: user is wrapping up a change → offer `/pre-push-review` before they push.
They ask for release notes → use `/changelog` rather than hand-writing a commit list.
They ask how the system fits together → offer `/arch-diagram`.

Not good: invoking a skill for a task it doesn't cover, or running one silently as a
side effect of an unrelated request.

**A project's own `CLAUDE.md` takes precedence over this file.**
