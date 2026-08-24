# Changelog

All notable changes to **nj-agents** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Initial public release of the toolkit. Everything below describes what nj-agents
does as of this version, rather than how it was built.

### Added

- **`evals/evals.json` — behavioral eval schema for `/pm-task`, adopting Anthropic's
  skill-creator schema verbatim** (`skill_name`, `evals[].{id,prompt,expected_output,
  files,expectations}`) rather than inventing a parallel format, so existing
  tooling built for that shape (the `eval-viewer`, the `grader` agent persona) works
  unmodified. 3 eval cases, 12 expectations total, grounded in `pm-task/SKILL.md`'s
  actual behavior (done-when requirement, propose-not-create default, scope
  discipline on an under-specified request). Investigating skill-creator's real
  tooling surfaced a correction worth recording: `run_eval.py`/`run_loop.py` test
  **trigger routing** via subprocess `claude -p` calls — a different concern from
  behavioral eval — while the `evals.json` → executor-subagent → grader-subagent →
  `grading.json` → eval-viewer flow is agent-orchestrated in skill-creator's own
  `SKILL.md`, not run by a script. `check_evals_schema` validates only the JSON
  *shape* where an `evals.json` exists (structural, same spirit as
  `check_skill_frontmatter`'s YAML check) — actually running the evals stays
  deliberately on-demand and never CI-gating, since each run spends real tokens on
  a with-skill + baseline subagent per case plus a grader subagent per run.

- **`check.sh` — artifact-level security scan of skills and agents.** A new
  `check_artifact_security` check scans skill files for what they would actually
  DO if executed, not just what they claim to do — the gap every other `check.sh`
  check leaves open, since they all validate a skill's stated contract (`tools:`
  frontmatter, "never runs git" prose) rather than its files' real behavior. Two
  lenses: code files (`scripts/*.py`/`*.js`/`*.sh`) are cross-referenced against
  the skill's own `## Dependencies` table — an undeclared network call is flagged,
  and a `curl`/`wget` piped straight into a shell always fails regardless of
  declaration, since that pattern has no legitimate reading inside a skill's own
  script. Prose (`SKILL.md`/`agents/*.md`) gets the same fetch-pipe-execute check,
  but only fails when there's no nearby human-facing framing ("do not install
  anything yourself") — otherwise every documented install instruction in the
  repo (e.g. `review-secrets`' trufflehog install block) would false-positive,
  which the check deliberately avoids per `CONVENTIONS-orchestration.md §C`
  ("a check that fires on everything is one people learn to ignore"). Verified
  live against all four cases: a clean pass on the current repo, an undeclared
  network call, a code-level install lure, and a prose-level install lure without
  human framing — all four caught correctly with `file:line`-level detail.

- **`check.sh` — deterministic self-tests for skills shipping `scripts/`.** A new
  `check_script_self_tests` check flags a skill's `scripts/` dir if it has `.py`
  files but no matching `test_*.py`. Added the first three: `test_make_cover.py`,
  `test_rasterize_svg.py`, and `test_publish_devto.py` for `/tech-blog`'s three
  scripts — stdlib `unittest`, tempdir fixtures, testing only the pure/deterministic
  logic (arg parsing, SVG dimension parsing, front-matter rewriting, path/scheme
  classification) since all three scripts shell out to Chrome or call Dev.to's API
  for their actual work, which a free, no-network self-test can't exercise. Writing
  `test_publish_devto.py` surfaced a real bug: `is_local()` misclassified a `data:`
  URI as a local file path (its regex required `scheme://`, but a URI scheme is just
  `scheme:` per RFC 3986) — fixed alongside the test that caught it.
  `skills/arch-diagram/scripts/` turned out to hold only a stale, gitignored
  `node_modules/` left over from the v0.4.0 rough.js-renderer removal (no script
  file, not referenced by `SKILL.md`) — removed rather than tested, since there was
  nothing there to test.

- **`check.sh` — trigger-routing regression tests for skill descriptions.** A new
  `check_description_routing` check (`scripts/gen-trigger-cases.sh`) extracts every
  quoted trigger phrase from all 38 skills' own `description` frontmatter — the same
  vocabulary a model reads to decide which skill matches a prompt — and verifies each
  phrase's own skill scores at least as high as every other skill against it, using a
  free, deterministic keyword-overlap heuristic (no network, no LLM). Catches two
  regression classes: a description edited down to something too generic to match its
  own trigger phrases (including one that loses its quoted phrases entirely, which
  would otherwise silently drop out of coverage), and two skills' descriptions
  drifting close enough to tie for the same prompt. 18 known-intentional collisions
  (umbrella/leaf pairs like `/pre-push-review` vs `/review-style`, close PM-authoring
  siblings) are allowlisted by exact prompt so they don't false-positive the gate; a
  genuinely new collision still fails it. A true model-judged routing test (not just
  keyword overlap) is deliberately out of scope for this free check — noted as a
  follow-up, not built here.

- **`/security-deep-review`** — an enterprise-depth, multi-agent security review,
  the first skill in the repo built on the Workflow tool rather than the informal
  "spawn N agents" prose pattern every other multi-agent skill here uses. Reuses
  `/review-secrets`' mandatory scanner gate unchanged, then runs a parallel
  multi-lens finder sweep (injection/authz, SSRF/deserialization/path-traversal,
  supply-chain, crypto/authn, cloud/infra), pipelines each candidate finding into
  independent adversarial verifiers (majority-refute kills it), and synthesizes one
  severity-ranked BLOCK/WARN/PASS report. Diff-scoped by default, `--full` opts into
  a whole-repo sweep. Deliberately invoked, not part of the default `/pre-push-review`
  fleet — the same relationship `/deps-upgrade` has to `/review-dependencies`. Adds
  two reusable agent personas, `security-finder` and `security-verifier`.

- **`/docs-site --docusaurus`** — a third output mode alongside the default generated
  MkDocs site and `--single`, for when the deliverable needs a branded look (custom
  navbar, optional React homepage, npm toolchain) that MkDocs Material's page shell
  doesn't offer. `docusaurus.config.ts` and `sidebars.ts` are still derived from the
  doc model rather than hand-written, but Docusaurus has no equivalent of
  `mkdocs-gen-files`'s virtual build-time tree — the generated `.mdx` pages are real
  files the generator overwrites, so this mode's anti-drift guarantee is weaker than
  the default and the skill says so explicitly.

- **`CONVENTIONS-pm.md` §P2c — change-nature labels on PM-authoring items.**
  `/pm-task`, `/pm-story`, `/pm-epic`, and `/pm-plan` (via `pm-decomposer`) now also
  include a change-nature label (`enhancement`/`bug`/`documentation`/`chore`) inferred
  from the item's type and content, when the connected tracker's own label set already
  has one of those — never inventing a new one. Previously these skills only applied a
  type label (epic/story/task) and any topic label, so a new-capability story landed
  with no `enhancement`-style label even on trackers (like GitHub) that ship one by
  default.

### Changed

- **One reference, not two: `docs.html` is removed and `/docs-site` now generates a site
  by default.** The repo carried two references — a hand-updated single-page `docs.html`
  and the generated MkDocs site — and they disagreed. That is worse than one dated doc,
  because a reader cannot tell which is current: `docs.html` had silently drifted to
  documenting 21 of 37 skills and 13 of 27 agents while the generated site was correct.
  The single-page file is deleted; the **generated site** (tree nav via `literate-nav`,
  one page per skill/agent/orchestrator, the architecture diagrams embedded, rebuilt from
  `skills/`/`agents/` on every build) is the reference.
  `/docs-site` flips to match: **Mode A, the generated multi-page site, is now the
  default**, and the self-contained single page moves to `--single` for hand-maintained
  prose or a no-toolchain deliverable — documented as a snapshot that will drift. The
  skill now also refuses to run both modes into one repo, commits the site's *inputs*
  rather than its build output, and must pass `mkdocs build --strict` before proposing a
  commit. `docs-designer` and the README/AGENTS.md rows follow.

- **PM-authoring items are now drafted to a cited industry standard, not house style.**
  `CONVENTIONS-pm.md` gains a **§P0** block pinning each type's complete required field
  set to its source — **INVEST** (stories), the **Scrum Guide** (Gherkin acceptance
  criteria, Definition of Done), and **SAFe** (Epic→Story→Task hierarchy, epic
  hypothesis). `/pm-epic`, `/pm-story`, `/pm-task` and `/pm-plan` reference §P0 and
  expand their Step-2 field lists to be standard-complete; each skill's description and
  the README/AGENTS.md tables now surface the standard as a selling point. (PMP/CSM/PSM
  certify practitioners, not issue formats — the docs cite the format-governing
  standards instead.)

- **GitHub Issues mapping now uses native sub-issues, not a body-reference workaround.**
  §P2's GitHub column was stale ("no native Epic/subtask — reference in body"). GitHub
  ships native sub-issues (100 children/parent, 8 levels deep, same on the free tier),
  so the model is now: **Epic = Issue** `[Epic] …`, **Story = sub-issue** `[Story] …`,
  **Task = sub-issue** `[Task] …` — each with a `[Type]` title prefix **and** an
  `epic`/`story`/`task` label (GitHub free has no native issue-type). The Project (v2)
  board is a cross-epic roadmap filtered by label, never a hierarchy level. `parent` is
  wired with `addSubIssue` (GraphQL). §P4 search-before-create strips the `[Type]` prefix
  when matching so a re-run links instead of duplicating. `§P2` and all four `/pm-*`
  skills updated.

### Fixed

- **The skill-suggestion hook never fired on most ways of saying "the design is
  wrong".** The design case required the literal string `"the design"`, so **four of one
  session's seven complaints missed** — including *"i dont see the design changes"*,
  which is the clearest possible call for `/claude-design-pull`. "old design", "new
  design" and the recurring typo "desing" all slipped through, and two phases of a
  redesign shipped against the wrong mockup without the gate ever being suggested.
  Design parity moved to its own block, because "design" is both a noun ("match this
  design") and a verb ("design me a schema") and one glob list cannot separate them.
  Unambiguous nouns fire (`mockup`, `figma`, `design system`, `redesign`); an
  instruction to invent never does (`design a…`, `design the…`, `designing…`); and bare
  `design`/`desing` fires only beside a look-at-the-screen word (*see, match, old, new,
  slide, page, layout, colour, pdf…*). 18 real phrasings check out in both directions.

  `check.sh` gains **`check_hook_fires`**, which asserts the hook actually suggests the
  right skill for prompts users really sent. The existing `check_hook_sync` only proved
  a skill was *named* somewhere in the file — a pattern too narrow to ever match passed
  it, which is exactly how this drifted. Verified by reverting to the old pattern and
  confirming the new check fails.

- **`/claude-design-pull` reported full coverage of a mockup it could not address at
  all.** `auditCoverage()` derived `complete` from `missing.length === 0`, which is
  vacuously true when the mockup has no classes to miss — so a fully inline-styled
  document (one run met a 1497-line deck with `class=` appearing **zero** times) audited
  as completely covered. That is the gate's own worst failure mode, a confident verdict
  over nothing, and the same shape as the hand-picked-manifest hole it was built to
  close. `complete` now requires `total > 0`, and a new `classless` flag says *why* so
  the caller can switch to structural anchors (a repeating element plus a stable
  attribute) instead of silently measuring nothing. Four regression cases added.

- **The same skill had no answer for a classless mockup, and no instruction to render
  the design at all.** Both gaps showed up on the same run: two phases of a redesign
  shipped against a subagent's *summary* of a mockup plus a stripped text export —
  accurate on palette, silent on layout, because neither preserved structure — and were
  reported complete twice before the user said the design had not changed. `SKILL.md`
  now (a) requires rendering the mockup via `render_preview` + Playwright rather than
  only reading its source, with the `serve_url` token-handling rule and the PDF recipe,
  and (b) tells the reader what to do when there are no classes to map. Recorded as
  failure 8 in the skill's header, because the most expensive way to skip a gate is to
  never invoke it.

- **A correct generated site reported as broken, because it was opened from disk.**
  Material builds *directory* URLs (`href="skills/foo/"`), which a browser cannot resolve
  over `file://` — so opening the built `index.html` lands every link on a directory
  instead of its `index.html`, and the page renders as unstyled HTML that reads exactly
  like a broken build. `/docs-site` now **never hands over a file path for a generated
  site**: it starts the server, confirms the page returns `200`, and gives a served URL
  *including any base path* from `site_url` (a GitHub Pages project site serves under
  `/<repo>/`, so a bare `127.0.0.1:8000` link 404s on the first click). The same note is
  in `CLAUDE.md` beside this repo's build recipe.

- **The testing class generated no documentation pages at all.** `docs_src/gen_pages.py`
  keys page generation off a `CLASSES` map that never listed `testing`, so all ten
  testing skills were invisible in the reference site. It stayed hidden until
  `/test-report` referenced `docs-designer`: the derived wiring then linked to a
  `skills/test-report.md` that was never generated, and `mkdocs build --strict` failed on
  the dangling link — breaking CI. Adding the class fixes the build and surfaces the ten
  missing pages. The general lesson is now recorded in `CLAUDE.md` and in `/docs-site`:
  a generator that silently skips an unknown entity type hides work rather than failing.

- **A permission-denied secret scanner was misread as a failed scan.** In a sandboxed
  or non-interactive runner, a compound gitleaks command (`echo … && gitleaks … | tail`)
  gets each part approval-gated and can be **denied** — which looked like the scanner
  failing when it never ran. `CONVENTIONS.md §3`, `/review-secrets`, and
  `/pre-push-review` now say: run the scanner as **one bare command, never chained**;
  and **"no scanner" (BLOCK) is not the same as "scanner blocked by the sandbox"**
  (an operator fix — confirm with `command -v`, run bare, or allow-list
  `Bash(gitleaks:*)`). Only a genuinely missing scanner or a real hit is a BLOCK.

- **A clean working tree made `/pre-push-review` exit 2.** The skill said "report
  and stop" without naming a verdict, and `bin/nj-agents-review` maps a missing
  verdict to exit 2 — a harness error. So a pre-push hook on a repo with nothing to
  review **blocked the push**, silently and for no reason.
  Two things were wrong, and 17 of 18 spawning skills had the same gap. **Nothing to
  do is a PASS**, not an error — a gate that found nothing wrong ran successfully.
  And the check belongs **before any dispatch**: five agents sent to confirm a clean
  tree cost real money to repeat what `git status` already said.
  Now a `§U` rule binding every skill, with `check_empty_input_pass` enforcing it.
  Five skills were fixed to state their own empty case (`/pr-describe`,
  `/review-correctness`, `/review-style`, `/dead-code-finder`, `/social-post`).

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
  First skills in the class: **`/e2e-run`** and **`/test-triage`**. Detects the repo's own
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
  **`/e2e-suite`** is the umbrella: run, classify, one PASS/WARN/BLOCK, mirroring
  `/pre-push-review`. Cost scales with *failures* rather than specs, so a green suite
  is nearly free. It **never repairs anything** — `/test-repair` is deliberately
  outside the pipeline, because a gate that fixes its own failures is not a gate.
  A test bug is **WARN, never PASS**: the application is fine but the suite is lying,
  and a broken test reporting green is how coverage quietly disappears.
  **`/test-report`** is the traceability matrix — requirement → case → spec → status
  → defect — and it **leads with what is not covered**. A report that lists passes
  reads as "we tested this", and a pass rate is not coverage: 98% passing says
  nothing about the untested 40% of a requirement. It also weights passes by flake
  history, since a green run resting on three known-flaky specs is a different
  result. It states the release position and stops; whether that is acceptable needs
  business context this skill does not have.
  **`/test-suite-author`** is the *generation* umbrella to `/e2e-suite`'s execution
  one: ticket → cases → specs → fixtures, chaining `/test-plan` → `/test-author` →
  `/test-data` in a single run. It **pauses after every stage**, because each is
  wrong in a different way and the cheapest place to catch each is immediately after
  it — the plan especially, where the judgement lives and the downstream stages are
  mechanical. `--yes` skips the prompts for a workflow but removes no constraint:
  it still never commits, still never weakens an assertion, still BLOCKs where it
  would have BLOCKed interactively. On approval it files the *uncovered* cases as
  `TEST-`-prefixed sub-tasks under the parent ticket via `/pm-task`, so an approved
  plan stops living only in a temp file where nobody but the person who ran it can
  see it. §P4 search-before-create makes a re-run link what exists rather than
  duplicating it — and a re-run is the normal case, since a changed requirement
  regenerates the plan.
  All ten skills in the class now exist (34 skills total), across two umbrellas.
- **The flake ledger is written, not just read** (NAV-219). `/flake-watch` read
  `.nj-agents/flake-ledger.json` and nothing wrote it, so it reported "insufficient
  history" in every repo forever. Worse, `/test-triage` is deliberately barred from
  calling `flake` without ledger history — a single run cannot distinguish a flake
  from a real race condition — so with an empty ledger it could never reach that
  verdict and classified genuine flakes as defects. The read path was complete; the
  write path did not exist.
  `nj-run ledger record` accumulates runs, fails, first/last seen, and a
  fixed-length recent window. Bounded by construction: the file grows with the
  number of **specs**, not runs, which is what makes committing it tolerable.
  `/e2e-run` records every spec, **pass and fail** — a fail rate needs a
  denominator, and a ledger of failures alone cannot tell a flake from a spec that
  always fails.
  **Basename merging for renamed specs was implemented, tested, and removed.** It
  fails in both directions and the failures are not symmetric: a missed merge loses
  history and is recoverable by passing `--id`, while a wrong merge *fabricates* a
  fail rate someone acts on. Three files named `login.spec.ts` in different
  directories collapsed into one record under every "merge only when unambiguous"
  rule attempted, because each merge rewrites the record's path so the next scan
  sees a single match again. §T14 asks for "a stable identifier plus a path
  fallback": `--id` is the identifier, exact-path is the fallback, and guessing an
  identity the caller never supplied is neither.

- **`/test-report --html`** renders the same report as a self-contained page. Not a
  second report — one model, two renderings, because a dashboard computing its own
  idea of "covered" would eventually disagree with the markdown and then neither is
  trustworthy. What the page adds is what a table cannot show: **per-spec trend**
  from the ledger's recent window, since §T14 holds that trend matters more than
  magnitude — a spec that went 0% → 15% is a regression someone introduced, a steady
  4% is a known cost. Fail rates always carry their denominator (`18% (9/50)`, never
  a bare `18%`), and specs below the sample floor render as "insufficient history"
  rather than a number that will be believed. NOT COVERED stays first and visually
  dominant; that ordering is the whole argument of the report and had to survive the
  change of medium. Output stays in the gitignored report dir unless given an
  explicit path, so `§T1` still holds.

- **A per-project push gate for the testing class** — `hooks/git/pre-push-e2e`,
  installed with `./install.sh --git-hooks --project DIR`. It refuses a push whose
  test suite is red, and **spends nothing**: it runs the repo's own test command and
  honours the exit code, with no agent and no API call. `check.yml` and
  `hooks/git/pre-push` had both already recorded that per-push LLM spend is
  unacceptable, and `/e2e-suite` costs 1 + n agents (one per failure), so it is a
  worse fit for a push hook than the review those files exclude. The paid triage
  moves to CI once per PR via the new **`bin/nj-agents-e2e`**, which maps the verdict
  to an exit code — `claude -p` alone exits 0 whatever the verdict.
  **§T3 had inverted on an unconfigured repo, and the gate is what exposed it.**
  `/e2e-run` resolved the base URL *before* detecting a runner, and §T3 says
  "unrecognised is BLOCK" — so a repo with no E2E tests and no `NJ_E2E_BASE_URL`
  produced the same BLOCK as one pointed at production. Wired into a hook that
  refuses every push in every unconfigured repo, while looking exactly like the
  safety rail working. Detection now runs first, and "nothing to run" is a SKIP.
  The clause is narrowed in **when it applies**, never in **what it allows**: once a
  runner exists, an unrecognised URL still stops the run.
  Three things the gate refuses to do, each enforced by `check_push_gate` rather
  than merely intended: **call an LLM**, **trust a runner that resolves to zero
  specs** (GitHub #9 — a config left behind after its specs were deleted detects
  cleanly and matches nothing), and **exit silently** (a gate that goes quiet is
  indistinguishable from one that was uninstalled, so every path prints its reason).
  Writing those found two real defects. The gate's runner probe originally accepted
  a bare `test` script — usually the *unit* suite, so it would have duplicated what
  already runs on commit while reporting itself as an E2E gate. And the
  resolves-to-specs check keyed on the word "playwright" in the command, which is
  absent when the entry point is `npm run test:e2e`, so it never fired. Both caught
  by running against `tests/fixtures/`, not by reading the code.

- **`/claude-design-pull`** — a review gate that answers "does this page match its
  approved design?" with measurements rather than an opinion. The mirror of
  `/design-sync`: that pushes a component library **to** Claude Design, this pulls
  approved mockups **into** a repo and holds the running code to them. Renders both
  sides headless through identical extractor code, diffs structure and computed
  styles element by element, and BLOCKs while they differ. Advise-only — it measures
  and reports, never edits application code, because a gate that fixes its own
  failures cannot tell you whether it ever failed.
  Written after a session that spent ten commits converging on one visual direction
  while repeatedly reporting success. Each of the four failures is now a case in the
  regression suite: a page built from *memory* of a mockup; `--radius: 1.25rem`
  making every control 18px instead of 6px, invisible to eyeballing and obvious in
  one computed-style dump; a toolbar rebuilt while its table kept the old columns;
  and "12/12 matching" reported as page-level success when it described twelve
  properties.
  That last one shapes the output: **no score, no percentage, no partial credit.**
  Either the page matches or the report is the list of what differs — a number is
  how a wrong page reads as progress. Data gaps are the deliberate exception and
  **WARN rather than BLOCK**, so the gate never pressures anyone into faking data to
  go green; when a design shows a field the API cannot supply, the honest fix is an
  API change.
  Playwright is **required with no eyeball fallback**, mirroring `/review-secrets`
  blocking without a scanner — a "best-effort visual check" is precisely what
  produced the four failures. Mockups are committed, so the gate runs offline and in
  CI with no MCP connection, is reviewable in a PR, and cannot change silently when
  someone edits the design project.
  Ships with `design-parity-checker` (one agent per page, no fix loop, so cost is
  bounded by page count) and four `lib/` modules, each carrying an assert-based
  self-check plus `known-bad.test.mjs`, which replays the real failures. Every case
  in it is a state the code was actually in and was reported as "done" at the time.

- **`bin/nj-run`** — the testing class's run harness, implementing §T10 cost
  accounting, §T11 subagent records and deterministic aggregation, §T12 the
  structured log, and §T13 the run manifest. `/e2e-run` and `/e2e-suite` now go
  through it instead of describing a manifest each would have written by hand.
  One shared tool rather than per-skill JSON because that is §T13's actual point:
  an umbrella can only report cost and subagent records uniformly if they are
  *recorded* uniformly, and a cost baseline computed by two code paths compares the
  code rather than the runs.
  Two behaviours are easy to lose in a hand-rolled reduce, so the harness owns them:
  a **quarantined subagent forces BLOCK** rather than being outvoted by the
  dimensions that did complete (four of five triages completing is not a complete
  triage), and **no dimensions, or all `SKIP`, is a PASS** (§U) rather than an
  ambiguous exit 2 that blocks a push for no reason.
  The append-only log is **published text**, so it passes the §T4 scrub even though
  the artifact-export prohibition does not apply to it — a bearer token in a
  heartbeat reaches a report with no artifact ever moving. Masked, never deleted:
  `Bearer ***` tells a reader an auth header was present, which is often the
  diagnostic detail.
  `tests/test-nj-run.sh` (18 checks, no LLM, CI-safe) and `check_run_harness` keep
  it honest. Writing those found a real leak: the vendor-key pattern used `\b`, a
  GNU extension that BSD `sed` treats literally, so `sk-…` keys passed through
  unmasked on macOS while the query-param mask worked — a weaker test would have
  called it clean.
  Detected-never-required like everything else (§A5): absent, a skill hand-writes
  the §T13 fields and reports that cost and log fields are missing.

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
