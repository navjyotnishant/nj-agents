# Changelog

All notable changes to **nj-agents** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Initial public release of the toolkit. Everything below describes what nj-agents
does as of this version, rather than how it was built.

### Fixed

- **`/commit-assistant` and `/pre-push-review` would not load on Codex CLI.** Their
  `description:` frontmatter was an unquoted YAML scalar containing `": "`, which
  YAML reads as a nested mapping — so the frontmatter was invalid, and Codex
  refused both skills outright (`invalid YAML: mapping values are not allowed in
  this context`). Claude Code and Gemini parse them anyway, which is why it went
  unnoticed: a lenient reader hid a genuine defect. Both values are now quoted.
  `check.sh` fails any unquoted frontmatter value containing `": "`, so a strict
  runner can no longer be the only thing that notices.

### Changed

- **Architecture diagrams no longer carry file-tree counts.** "23 skills",
  "25 agents", "6 gates" and the like were drawn into the SVGs, which meant every
  one went stale the moment a skill was added — silently, and correctable only by
  redrawing the diagram. They now live in the caption underneath, where the README
  needs a one-line edit and the docs site generates them from the source on every
  build. The artwork keeps what it can state truthfully forever: the *shapes* (15
  hexagons say "fifteen" without asserting it) and genuine structural facts like
  "1 level deep, always" and "0 commits made for you".
  `check.sh` enforces this going forward, and `/arch-diagram` documents the test:
  if adding a file would falsify it, it is a tally and belongs in the caption.

### Added

- **`CONVENTIONS-testing.md`** — the contract for a fifth skill class. It exists
  because of blast radius, not taxonomy: a testing skill **writes test source into
  the repo and then executes it against a running application**, and no existing
  class does either. `/review-tests-build` runs commands but writes nothing;
  `/test-gap-finder` reads coverage and never writes a test.
  Fourteen clauses, mostly prohibitions, because a suite that can edit and run itself
  has two failure modes nobody notices for months: it goes green by weakening its
  own assertions (**T2**), and it publishes a credential it captured from a real
  session (**T4**). T1 (source fence), T2, and T3 (non-prod URL gate) are **enforced
  by `check.sh`**, not merely stated — a skill that omits one is a finding.
  T4 is deliberately *containment* rather than redaction: raw traces and HARs never
  leave the gitignored temp dir, and text derived from them is scrubbed before it
  reaches a report or ticket. Full artifact redaction is the unlock condition for
  export, and is out of scope until someone actually needs a HAR on a ticket.
  Two clauses settle state: **T13** puts every skill behind a shared run manifest
  rather than letting them call each other, so each stays independently runnable and
  testable. **T14** puts the flake ledger at a *committed* `.nj-agents/flake-ledger.json`
  — gitignored it would start empty on every CI runner, which is exactly where
  intermittent failures accumulate and where the history is worth most.
  First skills in the class (31 skills now): **`/e2e-run`** and **`/test-triage`**. Detects the repo's own
  E2E runner — Playwright, Cypress, WebdriverIO, or whatever its config points at —
  BLOCKs unless the base URL is explicitly non-prod, runs the suite, and captures
  trace/HAR/video/console into a gitignored temp dir. It runs tests; it never writes
  or edits them, so there is no path on which it makes a suite green.
  **`/test-triage`** explains a red build — classifying each failure as real defect,
  test bug, environment, flake, or data, each with a confidence and cited evidence,
  and blaming suspect commits. It is the skill the class lives or dies on: weak
  triage teaches a team that red means "run it again", and once that habit forms
  everything upstream is shelfware. It **never calls `flake` from a single run** —
  timing-flavoured failure text looks identical to a real race condition in the
  application, and calling that a flake is how a concurrency bug gets ignored for a
  quarter. Advises only; hands defects to `/pm-task` on your say-so.
  **`/flake-watch`** reads that ledger and reports the accumulated picture: fail rate
  per spec, what is trending worse, what crosses the quarantine threshold. Three
  rules keep it honest — it reports **"insufficient history"** rather than a rate
  from three runs (a percentage will be believed), it treats **trend** as more
  informative than magnitude (a spec that went 0% → 15% is a regression someone
  introduced; a steady 4% is a known cost), and it routes a **100%-failing spec to
  `/test-triage`** rather than quarantining it — that is a defect wearing a flake
  costume, and hiding it behind flake accounting is the failure the ledger exists to
  prevent. Quarantine is always a proposal carrying an SLA and a tracking issue.
  **`/test-plan`** turns a requirement into a structured case matrix — equivalence
  classes, boundaries, negative paths and authz, not just the happy path, which is
  the case least likely to break and the one generation defaults to. Emits JSON for
  `/test-author` rather than prose, and marks inferred cases so a reviewer knows
  which came from the ticket and which from judgement.
  **`/test-author`** generates specs in **the repo's own framework**, never one it
  picks, matching the style of an existing spec. It enforces a `data-testid` locator
  contract and flags brittle selectors — and where the app has no testids it
  *proposes* adding them rather than reaching into application source, which T1
  fences it out of.
  **`/test-data`** generates fixtures and factories so each spec owns its data:
  unique per run, created by the spec, cleaned up after. Shared mutable fixtures are
  the usual cause of a suite that passes alone and fails in parallel — a data problem
  that gets diagnosed as flake, quarantined, and eventually deleted.
  Both writing skills propose the commit and never run git (T6), and neither writes
  a credential to disk (T8).
  **`/test-repair`** fixes a test only where the *test* is at fault. It fires solely
  on `/test-triage`'s `test-bug` verdict; every other classification BLOCKs —
  including `flake`, deliberately, because every available repair for a flake is
  forbidden (a sleep, a retry, a loosened assertion) and the honest responses are a
  real fix or quarantine with an SLA. It may fix selectors, waits, setup and
  teardown; it may **not** weaken or delete an assertion, add a sleep, raise a retry,
  or add a skip, and anything touching an assertion escalates rather than appearing
  in the diff. Where the correct fix is in application source it reports that and
  stops. Evidence outranks the label: if a failure looks like a defect it stops even
  when triage said test-bug.
- **`bin/nj-agents-review` drives any agent CLI** via `NJ_AGENT_CMD`
  (`NJ_AGENT_CMD="codex exec" nj-agents-review`). The verdict→exit-code mapping —
  0 PASS/WARN, 1 BLOCK, 2 harness error — is the value the wrapper adds, and it is
  not Claude-specific: `claude -p` exits 0 whether the review passed or blocked, and
  so does every other agent CLI. With a custom runner the Claude-only flags
  (`--output-format json`, `--max-budget-usd`, `--model`) are dropped, since another
  CLI would reject them, and the verdict is read from prose instead. `check.sh`
  asserts all four exit codes against stub CLIs.
  **Not yet verified against a real non-Claude runner** — Codex is over its usage
  limit and Gemini's free tier refuses its CLI client. The plumbing is there; the
  proof is not.
- **`tests/run.sh` no longer defaults to `haiku`.** With `NJ_TEST_MODEL` unset it
  uses the runner's own default. The old default meant every behavioural fixture was
  verified on a model nobody actually runs the skills with — and a smaller model
  follows a skill more literally, so a fixture could pass there and fail in use.
  Setting `NJ_TEST_MODEL=haiku` for a cheap pass still works, now as a deliberate
  choice rather than a silent one.
  This generator stays Claude-Code-only by construction (it needs
  `--output-format json`, `--permission-mode`, `--max-budget-usd`), and now says so
  and exits rather than half-working if `NJ_AGENT_CMD` is set.
- **Cursor knows the toolkit exists.** Cursor reads guidance as `.mdc` in
  `.cursor/rules/` with real YAML frontmatter, so `global/AGENTS.md` cannot be
  symlinked there the way `CLAUDE.md` and `GEMINI.md` can. `./install.sh --runner
  cursor` generates the rule instead — deliberately a **pointer, not a copy**.
  Cursor's own `create-rule` skill says rules should stay "under 50 lines" and be
  "concise and to the point"; converting 240 lines of standing rules into an
  always-on rule would cost context on every request. The generated rule names the
  five classes, lists their skills, states the guarantees every skill makes, and
  points at `global/AGENTS.md` for the rest — 33 lines. `check.sh` fails it if it
  outgrows the budget, and the skill lists are read from the file tree so they
  cannot drift.
- **Codex gets the agents too.** Codex reads agents as TOML rather than markdown
  with YAML frontmatter — a different *format*, not a different path, so the 25
  `agents/*.md` cannot be symlinked there the way skills can. `./install.sh
  --runner codex` now **generates** them, following the schema in Codex's own
  `migrate-to-codex` converter (`name` / `description` / `developer_instructions`).
  Before this, Codex had skills but no agents, so the 17 skills that delegate
  would have run everything inline there.
  Generated files are build artifacts: rewritten on every install, never
  committed, and each carries a header saying so. Uninstall removes them, but
  leaves a `.toml` you wrote yourself alone. `check.sh` generates into a temp
  directory and parses the result, so a broken generator fails the build rather
  than silently producing agents Codex skips.
  Note `tools:` becomes prompt guidance rather than a permission on Codex — the
  vendor's own converter does the same, since Codex enforces via `sandbox_mode`
  and `[permissions]`, which are a per-user decision this does not make for you.
- **`/screenshot-docs-sync`** — keeps documentation and its embedded screenshots
  current as the UI drifts. Diffs since the last doc update, works out which doc
  sections went stale, re-captures only the affected screens, and edits in place.
  Where `/capture-screenshots` is the one-shot capture, this is the maintenance
  loop. Same redaction discipline; proposes the commit. (24 skills now.)
- `./install.sh` reports what it did instead of scrolling 50 near-identical link
  lines past the one that mattered: how many links were new, already current, or
  **repaired because they were dangling** — plus two things it deliberately does
  not change. A real file where a symlink belongs means your copy has stopped
  tracking the repo. A skill or hook sitting in the config directory that is not
  in the repo is not version-controlled and not installed for any other runner.
  Both are now listed rather than silently skipped.

- The global guidance file is now **`global/AGENTS.md`** — one canonical copy that
  every runner reads. `install.sh` symlinks it to `~/.claude/CLAUDE.md`,
  `~/.codex/AGENTS.md`, or `~/.gemini/GEMINI.md` depending on `--runner`, so all
  three resolve to the same bytes and there is no per-runner variant to keep in
  sync. `AGENTS.md` is the name the ecosystem is converging on.
  `check.sh` gained a size assertion: Codex silently truncates `AGENTS.md` past
  32 KiB, and truncation gives no signal — the guidance just stops applying
  part-way through. The file is 16 KiB today, so this is a tripwire for the edit
  that would push it over.

  **Upgrading:** the rename orphans an existing `~/.claude/CLAUDE.md` symlink,
  which will point at a path that no longer exists. Re-run `./install.sh` to
  repair it.
- `./install.sh --runner claude|codex|cursor|gemini|agents` installs into that
  agent's own config directory, with the global guidance file linked under the
  name it reads (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md`). `claude` remains the
  default, so a bare `./install.sh` behaves exactly as before.
  Because everything is a symlink back into the clone, **installing for several
  runners leaves them all reading the same files** — edit a skill once and every
  runner sees it, with nothing to sync. `--project DIR` honours the runner too.
  Codex (agents are TOML) and Cursor (guidance is `.mdc`) need a generator rather
  than a symlink; until those land the installer **skips those pieces and says
  so** rather than leaving files the tool silently ignores.
  `check.sh` gained a check that installs into a temp directory and asserts every
  runner resolves back to this one clone, so the claim is tested rather than
  documented.

### Changed

- **`/commit-assistant` now offers to run the commits it drafts.** It still prints
  the `git add` + `git commit` block first, every time — that block stands on its
  own and copying it works exactly as before. But re-typing a command you have just
  read and approved is friction, not safety, so it then asks.
  **Once per commit, never once for the batch**: splitting unrelated changes is the
  skill's whole point, and a single yes covering three commits approves messages you
  have not seen land. Each prompt shows the exact paths it would stage, because the
  thing being approved is a set of files, not a sentence. `[y]` run · `[n]` skip ·
  `[e]` edit the message · `[a]` stop.
  It re-reads the tree between commits (committing changes what is staged), halts on
  the first failure rather than retrying, and **never pushes, never tags, never
  `--no-verify`**. In CI it prints and stops — there is nobody to ask.
  This does not weaken §U's *the human decides what gets committed*: that rule
  forbids running git on the skill's **own initiative** and explicitly allows an
  explicit go-ahead. `check.sh` now enforces the distinction — a workflow skill that
  runs `git commit` must name an approval gate, or it fails.
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
