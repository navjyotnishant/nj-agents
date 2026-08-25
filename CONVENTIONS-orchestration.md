# nj-agents — shared cross-class conventions

Rules that hold across every class. **§U** binds *every* skill in the toolkit; **§C**
and **§R** bind any skill that spawns subagents. Where the per-class
conventions docs (`CONVENTIONS.md`, `CONVENTIONS-authoring.md`, `CONVENTIONS-pm.md`)
say *what* a class produces, this one says how a skill behaves while producing it:
what it costs (`§C`) and what the developer sees while it runs (`§R`).

It is deliberately class-agnostic. Cost control originally lived in
`CONVENTIONS.md §8`, the review-class doc — which meant authoring and PM skills, the
ones running the longest pipelines in the toolkit, had no cost rules to cite. A
skill spawning six agents costs the same whatever class it belongs to.

**Who this binds:** every skill whose procedure spawns an agent. `check.sh` detects
that from the skill's own text rather than a list of names, so a skill added
tomorrow is covered the moment it says "spawn".

---

## §U — Universal (every skill, every class)

These hold regardless of what a skill produces. They were previously restated in each
class doc, which meant they drifted — "no secrets" appeared in two, "ground
everything" in one, so a PM skill was never formally bound by the grounding rule at
all despite it obviously applying.

**Ground everything in the actual repo.** Read the README, the docs, the code. Never
invent an API, a file path, a version, a benchmark, or a component. A claim you cannot
verify gets cut or explicitly marked — never smoothed over. This is `§A6` for
authoring, `§P1` for PM, and it applies to the rest too.

**The human decides what gets committed.** No skill runs `git add`, `commit`, `push`,
or `tag` on its own initiative — it writes the artifact and prints the exact commands.
An explicit "commit and push" from the user overrides this, nothing else does. Never
`--no-verify`.

**No secrets in output.** Never put a credential, token, internal hostname, or private
URL into a file, a tracker item, a commit message, or a report. On a suspected secret,
stop and say so rather than including it redacted-but-present.

**Keep `CHANGELOG.md` current when the change is user-facing.** A feature, a fix, a
breaking change or a deprecation goes under `[Unreleased]` **as it lands** — not
reconstructed at release time, when the reasons are gone. Use `/changelog`. Refactors,
tests, docs-only edits and internal tooling do **not** belong there: a changelog that
records everything records nothing. If the repo has no `CHANGELOG.md`, offer to start
one rather than letting the gap grow — but never hard-block a throwaway repo over it.

**Document every external dependency, with its fallback.** A skill that shells out to
anything not in a POSIX base install states it in a `## Dependencies` table: the tool,
what it is used for, and what happens without it. A reader must be able to see what a
skill needs *before* running it, not discover it from an error. Buried in prose does
not count — it has to be scannable.

| Tool | Used for | Without it |
|---|---|---|
| `example` | what it does here | the documented fallback, or BLOCK if genuinely required |

**Nothing to do is a PASS, and it is checked BEFORE spawning anything.** If the
input a skill exists to process is empty — no uncommitted changes, no failures, no
outdated dependencies, no requirement — the skill reports that and **returns
successfully**. It does not spawn an agent to confirm the absence.

Two distinct failures here, and both are common:

- **Spawning anyway.** Five agents dispatched to review a clean tree costs real
  money to be told there is nothing to review. The precondition check is free and
  comes first — before the roster is announced, before the cost is stated, before
  any dispatch.
- **Reporting it as an error.** "Nothing to review" is a *successful* run of a gate
  that found nothing wrong. A skill that stops without naming a verdict leaves the
  caller to guess, and `bin/nj-agents-review` maps a missing verdict to **exit 2,
  harness error** — so a clean working tree fails a pre-push hook. That is the
  opposite of the intended behaviour, and it is silent until someone's push is
  blocked for no reason.

So: **say PASS explicitly**, say why there was nothing to do, and exit 0. Reserve
non-zero for a real finding (BLOCK, exit 1) or a run that could not reach a verdict
(exit 2). An empty input is neither.

The same holds per-dimension inside an umbrella: a dimension with nothing to review
is a `SKIP` with a labeled reason, not a spawned agent and not a failure.

**Degrade, don't fail.** External tools and MCP connectors are detected at runtime,
never required; every path has a zero-dependency fallback. The one exception is secret
scanning, which genuinely blocks without a scanner.

**Assume nothing about which agent is running you.** One clone installs into Claude
Code, Codex, Cursor and Gemini, so a skill or agent that names a vendor is wrong on
three runners out of four — and wrong *silently*, since nothing errors.

- Say **"this session"**, never "this *<vendor>* session". The privacy claim is true
  either way; the vendor name is the only part that can be false.
- **Never pin a model.** An agent omits `model:` so it inherits the session's — a
  pinned tier silently overrides the user's own choice. A skill never recommends one
  either: "run this on haiku" is a recommendation no other runner can honour.
- **Name a runner only when the difference is the point.** "Option B is Claude Code
  only" is correct and useful. "Shares your diff with Claude" is not.
- `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` are fine to **read as repo input** — they
  are real files in real repos whatever tool you run.

`check.sh`'s `check_vendor_neutral` enforces the first two, so this is a gate rather
than an aspiration. It is deliberately narrow: a skill may *discuss* a runner, and
several must.

**Verify a visual artifact by looking at it.** For anything rendered — a diagram, a
page, a screenshot — reading the source is not verification. A label hidden behind a
frame stroke, an arrowhead removed by a filter, a nav that a JS-loaded theme breaks:
all invisible in the source and obvious the moment it is rendered and viewed. Grepping
the built output is not looking at it.

**A number in an artifact is a claim.** Count it from the source before writing it
down. A diagram saying "7 agents" beside nine shapes, or a page claiming 12 skills
when there are 23, discredits everything around it — and the reader has no way to
know which other facts to distrust.

**Say what you did not do.** A skipped step, a partial scope, an unavailable tool —
state it plainly. An artifact that implies more coverage than it has is worse than one
that admits the gap.

---

## §C — Cost control (every skill that spawns agents)

Each subagent costs real money against the user's plan, and several skills here run
render→QA→fix or find→verify loops that can go many rounds. Treat spend as a budget
to manage, not an implementation detail.

**State the cost shape before spawning anything.** One line, before the first
dispatch, naming the fleet size and the loop shape — then, in interactive mode, get
a yes:

```
Scope: 12 files, 340 reviewable lines (2 lockfiles, 1 image excluded)
Plan:  5 dimension agents in parallel (secrets-semantic, correctness,
       tests/build, dependencies, style)
Proceed? [Y/n/pick dimensions]
```

For a loop, say the bound up front: *"render → QA → fix, usually 2–4 agent calls,
hard cap 2 fix rounds."* The user can accept, decline, or name a subset. Skip the
prompt only in non-interactive/CI mode (`CONVENTIONS.md §5`), where there is nobody
to ask.

**Scale the fleet to the work.** Do not spawn an agent that has nothing to do — a
skipped agent is free, and `SKIP — no dependency manifests changed` is more
informative than a report that spent tokens confirming it.

| Signal | Action |
|---|---|
| No dependency-manifest changes in the diff | `SKIP` the dependencies dimension |
| No test/lint/build command detected | `SKIP` tests/build (report the miss) |
| Docs-only diff (`*.md`, no source) | Offer style-only; skip correctness |
| Trivial diff (< ~20 lines, 1–2 files) | Offer a single inline review, no fleet |
| Very large diff (`CONVENTIONS.md §2` cap) | Say the review is partial, and that top-N scoping is what bounds the cost |

**Re-runs are the expensive case.** A user fixing findings will re-run. Default to
only the parts that still have open findings, and say so:

```
Re-run: correctness + style only (the 2 dimensions with open findings).
Add --all to re-review everything.
```

**Hard stops.**
- **Cap fix rounds at 2, then ASK.** After two cycles on the same artifact, stop and
  report what's fixed and what still fails — then offer the choice explicitly:
  *"Ship as-is, or run 2 more rounds?"* Never start a third round unprompted, and
  never quietly abandon the work either. The cap makes spend a decision rather than a
  side-effect; the question is what keeps it from becoming a dead end.
- **A blocking verdict is a checkpoint, not a to-do.** When a QA/review agent returns
  BLOCK, surface it — do not silently fix and re-run. Say what it found and what
  fixing it would cost.
- **Halt on any signal to stop** — "this is expensive", "that's taking a while", a
  suggested change of approach, or an interrupt. Do not acknowledge and continue.
- **Never chain into another agent-spawning skill** because this one suggested it.
  Report the finding; let the user invoke the fix.

**Cheap path first.** If a scanner, a linter, a one-line flag, or a single targeted
read answers the question, do that and offer the fleet as the upgrade. A skill is not
automatically the right tool because it matches the topic.

---

## §R — Progress reporting (every skill that spawns agents)

A subagent returns **once, at the end** — it has no channel to stream status while it
works. So the *spawning skill* is the only place that can make a multi-agent run
legible, and it must.

Without this, a six-agent pipeline is a silent gap ending in a wall of output, and
the developer cannot tell whether it is working, stuck, or looping.

**Announce the roster before dispatch.** Every agent, and what it will do:

```
Dispatching 5 agents in parallel:
  ⋯ secrets-reviewer      semantic security pass
  ⋯ correctness-reviewer  logic + regressions
  ⋯ tests-build-runner    detect and run the repo's commands
  ⋯ dependency-reviewer   manifest + license changes
  ⋯ style-reviewer        conventions + commit hygiene
```

**Mark each one as it lands**, with a one-line result — not a summary, the verdict:

```
  ✓ style-reviewer        PASS — no findings
  ✓ secrets-reviewer      WARN — 1 finding
  ✗ tests-build-runner    BLOCK — 3 tests failing
```

**Distinguish the two shapes**, because they read differently:

- **Parallel fan-out** — all dispatched at once; print the whole roster, then mark
  results as they arrive in whatever order they finish.
- **Sequential pipeline** — each stage feeds the next; print the chain
  (`blog-writer → blog-fact-checker → blog-reviewer → …`) and announce each stage as
  it starts, so a stall is attributable to a named stage.

**Loops report the round against the cap** — `round 2/2` — so a loop that looks
unbounded visibly shows its bound (`§C`).

The glyphs are a detail; the roster-then-drain shape is the requirement. What matters
is that at any moment the developer can see what was dispatched, what has come back,
and what is still outstanding.

## §M — Memory (run-level resumability + agent-level persistence)

Two genuinely different mechanisms get called "memory" in this repo, and conflating
them produces vague guidance neither skill authors nor `check.sh` can act on.
**Run-level** is the Workflow tool's own resumability, free and already built —
nothing to design, just adopt where the shape fits. **Agent-level** is a persona
remembering something *across separate runs*, which nothing in the harness provides
for free — an agent has no storage of its own, so this only works if the *skill*
that spawns it explicitly owns a memory file and feeds it in.

### §M1 — Run-level: `resumeFromRunId`

A Workflow-scripted skill gets this for nothing beyond stating it exists: on
`Workflow({scriptPath, resumeFromRunId})`, the longest unchanged prefix of `agent()`
calls returns cached results instantly — only the first edited/new call and
everything after it runs live (see the Workflow tool's own description for the
mechanics). This matters for exactly one failure mode: **a multi-stage pipeline
killed or interrupted partway through** — a long `pipeline()` chain (writer →
fact-checker → reviewer → editor) that dies after stage 2 currently means starting
over and re-paying for stages 1–2.

**When a migrated skill should document a resume path:**
- **Multi-stage `pipeline()` skills** (e.g. `/tech-blog`'s writer→fact-checker→
  reviewer→editor chain) — document the `runId` the tool returns, and tell the user
  to re-invoke with `resumeFromRunId` if a run is killed or fails partway through.
  This is a one-paragraph addition to the skill's own "how it runs" section, not new
  code — the resumability is the tool's, not the skill's.
- **Single-stage or pure `parallel()` skills** (e.g. `/pre-push-review`'s 4
  dimensions dispatched together, `/claude-design-pull`'s per-page fan-out) — resume
  matters less, since a killed run has little sunk cost to preserve; a bare mention
  that resume works if the user wants it is enough, no dedicated section needed.
- **Skills the user pauses deliberately** (`/test-suite-author`'s pause-after-every-
  stage design, §M below is separate from this) — each staged `workflow()`
  invocation is short enough that resume adds little; not worth documenting per
  §C's own "don't build ceremony nobody needs" spirit.

Never claim resumability for a skill that isn't Workflow-scripted — prose-orchestrated
skills have no `runId` to resume from, and saying otherwise would be inventing a
capability that doesn't exist for them.

### §M2 — Agent-level: what `memory: project` actually means

**As of this writing, `memory: project` is a recognized agent-frontmatter key with
no defined runtime semantics anywhere in this repo or the platforms it targets** —
it was documented as valid without ever being given a behavior. This section defines
one, grounded in what an agent persona can actually do:

An agent (`agents/*.md`) has no storage of its own — it is a system prompt plus a
tool list, spawned fresh each call. Per the write-discipline convention already in
`CLAUDE.md` ("23 of the 25 [agents] return content for the *skill* to write" — most
agents don't carry `Write`), an agent cannot durably persist anything itself even if
it wanted to. **So `memory: project` means: the *skill* that spawns this agent reads
a project-scoped memory file and includes its relevant contents in the agent's
prompt, and the skill writes back whatever the agent's return value says should be
remembered.** The frontmatter key is a declaration, not a capability grant — it
tells `check.sh` and a reader "this agent's persona expects prior-run context to be
fed in via its prompt; verify the spawning skill actually does that," the same
relationship `tools:` has to what an agent's body claims to do.

**Adoption criteria — when a NEW or existing agent should carry `memory: project`:**
an agent qualifies only if it repeatedly evaluates *the same kind of thing* across
separate runs of the same project, AND remembering prior context measurably reduces
redundant work or improves consistency (not just "might be nice to remember
something"). Two disqualifying patterns, both common enough to name explicitly:

- **A verify-only agent should not get memory.** `security-verifier`'s whole design
  is to judge one finding fresh, skeptically, blind to other verifiers' votes — an
  adversarial-refute pattern that depends on each vote being independent. Feeding it
  "here's what you decided last time" is a bias vector, not a helpful shortcut; it
  would erode exactly the independence the majority-vote scheme relies on.
- **A search agent whose ground shifts every run should not get memory either.**
  `security-finder` re-reads the actual diff/repo each call; "remembered" prior
  findings go stale the moment code changes, and a finder that trusts stale memory
  over what it just read is a finder that can miss a fix or a regression. Its
  confidence-filter-and-report design already handles repeat runs correctly —
  nothing here needs remembering.

**Worked example (evaluated, not adopted):** both `security-finder` and
`security-verifier` were evaluated against these criteria for this section and
**neither qualifies** — see the two disqualifying patterns above, which are their
exact shapes. No agent in this repo has yet been identified as a genuine fit; the
criteria exist so the next candidate (a persona doing repeated, project-scoped
comparison work where staleness isn't a risk — e.g. something like "has this exact
finding already been triaged and dismissed by a human") can be evaluated against a
real bar instead of a guess.
