---
name: pre-push-review
description: "Use this skill when the user asks to \"review my changes before I push\", \"run the pre-push review\", \"check this diff before committing/pushing\", \"do a thorough review of the current changes\", or wants an AI-assisted quality gate over the current commit or uncommitted work. Runs up to five review dimensions (secrets, correctness, tests/build, dependencies, style) via a Workflow-tool pipeline — the secret scan first as a gate, then the rest in parallel — and aggregates one PASS / WARN / BLOCK verdict with a report artifact. Cost-aware: it states the scope and agent count and asks before spawning, skips dimensions with nothing to review, and on a re-run defaults to only the dimensions that still have findings. Supports a non-interactive CI mode with an exit-code contract. Works in any git repo; nothing here is specific to one project, stack, or tool."
version: 0.5.0
class: review
subclass: gate
author: navjyotnishant
---

# Pre-Push Review (umbrella)

A thorough, AI-assisted review of the **current commit or uncommitted changes**
before they are pushed — or any time it is triggered manually or from CI. It
orchestrates five dedicated review dimensions:

- **secrets** — leaked credentials (scanner-first), plus semantic security
- **correctness** — logic bugs, regressions, edge cases, missing validation
- **tests/build** — auto-detected test/lint/build commands, run as a gate
- **dependencies** — added packages, version/license changes, supply-chain signals
- **style** — conventions, commit-message hygiene, leftover debug/TODO output

This is a **procedure, not a fixed script** — discover each repo's stack, branch
layout, and tooling at runtime. It **advises only**: it never pushes, commits, or
bypasses git hooks, and leaves no files in the repo. All shared behavior
(snapshot scope, diff hygiene, findings format, CI mode, report artifact, safety)
is defined once in **`CONVENTIONS.md`** — read it; the steps below reference it.

Scope resolution, the secret gate, and the cost/roster confirmation (Steps 1–3.5)
happen **before** any agent is spawned — these involve git commands, interactive
prompts, and stateful re-run logic that don't belong inside a script. Once the
fleet is confirmed, dispatch runs as a **`Workflow`-tool pipeline** (Step 4): the
confirmed dimensions in parallel, aggregated with plain logic (no LLM needed for a
mechanical max-severity rollup), then an optional trailing report-writer call —
gaining the same resumability and progress tree `/security-deep-review` has, on
the skill users hit most often.

> **Finding `CONVENTIONS.md`.** It lives at the toolkit repo root, two levels
> above this skill — not beside `SKILL.md`. Skills are usually installed as
> symlinks into your runner's skills directory, so a plain relative path resolves against
> the *link* and misses it. Resolve the link first:
>
> ```bash
> CONV="$(dirname "$(readlink -f "<this skill's base directory>")")/../CONVENTIONS.md"
> ```
>
> If it is genuinely absent, say so and continue with the procedure below rather
> than stopping — the steps here are self-contained enough to run without it, but
> the shared findings format and report layout will be approximated.

> **Every skill follows `CONVENTIONS-orchestration.md` §U** — ground everything in
> the actual repo, never run git on your own initiative, no secrets in output,
> keep `CHANGELOG.md` current when the change is user-facing, degrade rather than
> fail, and say what you did not do.

> **Spawning subagents — `CONVENTIONS-orchestration.md`.** This skill spawns agents
> via a `Workflow`-tool pipeline (Step 4), so `§C` (cost) and `§R` (progress
> reporting) apply. **Cost shape:** up to 5 dimension agents in parallel after the
> secret-scan gate, plus 1 report-writer after aggregation (Step 5.5) — so up to 6.
> State it and get a yes before the first dispatch; cap fix rounds at 2; halt on any
> signal to stop. Announce the **roster** before dispatch — every agent and what it
> will do — then mark each one `✓`/`✗` with its verdict as it lands (`§R`). The run
> is resumable via `resumeFromRunId` if interrupted (`§M1`) — worth mentioning to the
> user on a failure, not a dedicated section, since a pure-`parallel()` fleet like
> this one has little sunk cost to preserve on resume.


## Dependencies

Detected at runtime, never installed by this skill (`§A5`).

| Tool | Used for | Without it |
|---|---|---|
| `gitleaks` *or* `trufflehog` *or* `detect-secrets` | the secret gate that runs first, alone | **BLOCK** — the gate cannot be skipped |
| the repo's own test/lint/build commands | the tests-build dimension | `SKIP` that dimension and say so |

## Step 0 — Print the warning banner FIRST

Before running any git command or reading any diff, print this banner verbatim:

```
╔══════════════════════════════════════════════════════════════════╗
║  PRE-PUSH REVIEW — AI-ASSISTED                                    ║
╠══════════════════════════════════════════════════════════════════╣
║  This generates a SNAPSHOT of your changes (git diff of staged,   ║
║  unstaged, and committed-but-unpushed work) and shares it with    ║
║  AI (this session + its subagents) for review. No external        ║
║  API is called and nothing leaves this machine — the current      ║
║  session does the analysis.                                       ║
║                                                                   ║
║  BEFORE any snapshot is shared, a REQUIRED secret scanner         ║
║  (gitleaks / trufflehog / detect-secrets) runs. If none is        ║
║  installed the review BLOCKs with install steps. If a             ║
║  credential/key/token is detected, the review STOPS and shares    ║
║  nothing until you remove it.                                     ║
║                                                                   ║
║  This tool ADVISES only. It never pushes, commits, bypasses git   ║
║  hooks, or leaves files in your repo.                             ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository.** If `git rev-parse --git-dir` fails, stop and say so.
- **A diff to review.** If staged + unstaged + unpushed is all empty, report
  **PASS — nothing to review** and exit 0, *before spawning anything*. A clean tree
  is a successful gate, not an error: reporting it as one makes a pre-push hook
  reject a push that has nothing wrong with it (`§U`).
- **No external API key / no network.** Uses the current AI session; never asks
  for or requires any credential.
- **REQUIRED:** a dedicated secret scanner on PATH (`gitleaks` / `trufflehog` /
  `detect-secrets` — any one). If none is installed, the review BLOCKs with install
  instructions; there is no heuristic-only fallback gate.
- **Optional, auto-detected:** a test/lint/build command (tests/build dimension).
- **Optional:** a configured upstream (`@{upstream}`); else the unpushed scope falls
  back to the default branch (`CONVENTIONS.md §1`).

## Step 1 — Determine mode and check prerequisites

Detect interactive vs. non-interactive/CI mode per `CONVENTIONS.md §5`
(`NJ_AGENTS_CI=1`, a `--ci` arg, or the user saying it's for a pipeline/hook). In CI
mode, never prompt; resolve ambiguity to the safe (BLOCK) outcome and honor the
exit-code contract.

```bash
git rev-parse --git-dir >/dev/null 2>&1 || echo "Not a git repository."
```

If not a git repo, **stop with a harness error** — the skill cannot run at all.

If the combined diff is **empty**, that is different: report **PASS — nothing to
review**, exit 0, and **spawn nothing**. Do this here, before the roster is
announced and before any cost is stated. Five agents dispatched to confirm an empty
diff cost real money to tell you what `git status` already did.

The distinction matters because `bin/nj-agents-review` maps a missing verdict to
exit 2. "Nothing to review" without an explicit PASS reads as a harness error, and a
pre-push hook then blocks a clean push (`§U`).

## Step 2 — Build the snapshot and apply diff hygiene

Assemble the snapshot per `CONVENTIONS.md §1`, then apply diff hygiene per §2:
exclude lockfiles/binaries/generated/vendored files from the *semantic* review
(they're still secret-scanned), and if the reviewable diff is very large, plan a
partial top-N review and say so. Keep everything in the scratchpad/temp dir — never
write into the repo. Do **not** hand anything to a subagent yet.

## Step 3 — Secret-scan GATE (inline, first, before anything is shared)

Run the `review-secrets` gate (a **required** dedicated scanner) over the added
lines, per `skills/review-secrets/SKILL.md` and `CONVENTIONS.md §3`:

- **No scanner installed → BLOCK.** Print the install instructions and stop — do
  not spawn any agent, share nothing. The overall verdict is BLOCK; a push must not
  proceed without an authoritative secret scan.
- **Any scanner hit → STOP.** Print `file:line` + rule/pattern class + **masked**
  value. Do **not** spawn any agent; share nothing. Interactive: tell the user to
  remove/rotate (or allowlist a confirmed false positive) and re-run. CI: BLOCK,
  exit 1.
- **Clean → proceed to Step 4.**

**Run the scanner as ONE plain command — never chained.** A sandboxed/non-interactive
runner gates each part of a compound command (`&&`, `|`, `;`, `$(…)`) separately and
may **deny** it with no one to approve — which looks like "the scanner failed" when it
did not. Invoke it bare:

```bash
gitleaks git --log-opts="main..HEAD" --redact --no-banner -v
```

not folded into an `echo … && gitleaks … | tail` one-liner. If you need the exit code,
read `$?` on the *next* line, don't `&&`-chain it.

**Distinguish "no scanner" from "scanner blocked by the sandbox" — they are NOT the
same verdict.** Before declaring BLOCK-no-scanner, confirm the scanner is actually
absent (`command -v gitleaks`). If it **exists but the run was denied/approval-gated**,
that is an **operator/environment problem, not a code BLOCK** — say so plainly, do not
report the change as failing a secret scan, and unblock by either running the bare
command above or allow-listing it once:

```jsonc
// .claude/settings.json — makes the gate run unattended (read-only, safe)
{ "permissions": { "allow": ["Bash(gitleaks:*)"] } }
```

Only a genuinely missing scanner or a real hit is a BLOCK; a permission denial is a
setup fix.

Non-negotiable ordering: handing the diff to any subagent counts as "sharing with
AI," so secrets clears first.

## Step 3.5 — State the cost and confirm the fleet

Five subagents is the most expensive operation in this toolkit, and a user
iterating on findings will run it repeatedly. Before spawning anything, apply
`CONVENTIONS.md §8`:

1. **Decide which dimensions are worth running.** Skip any with nothing to
   review — no manifest changes means no dependencies agent, no detected test
   command means no tests/build agent. A `SKIP` with a reason is free and more
   informative than an agent that spends tokens confirming there was nothing to do.
2. **Print the scope and plan**, then get a yes (interactive mode only):

```
Scope: 12 files, 340 reviewable lines (2 lockfiles, 1 image excluded)
Plan:  4 dimension agents in parallel
       (secrets-semantic, correctness, tests/build, style)
       SKIP dependencies — no manifest changes in this diff
       + 1 report-writer after aggregation (HTML report) — 5 agents total
Proceed? [Y/n/pick dimensions]
```

3. **On a re-run**, default to the dimensions that last reported `WARN`/`BLOCK`
   and say so; the user can ask for `--all`.

In CI mode (`CONVENTIONS.md §5`) there is nobody to ask: skip the prompt, still
apply the skip rules, and record the fleet size in the report.

## Step 4 — Run the Workflow pipeline

See [`docs/architecture/pipeline-pre-push-review-nano.png`](../../docs/architecture/pipeline-pre-push-review-nano.png)
for the gate → parallel-review → aggregate → optional-report shape at a glance.

Once the snapshot is cleared **and the fleet is confirmed** (Step 3.5), hand this
script to the `Workflow` tool. `DIMENSIONS` is the post-skip list from Step 3.5;
`snapshot` is the cleared, hygiene-filtered diff; `wantHtml` is `true` only if the
caller passed `--html` or this isn't CI mode (Step 5.5's existing rule).

```js
export const meta = {
  name: 'pre-push-review',
  description: 'Parallel review dimensions, mechanical aggregation, optional HTML report',
  phases: [
    { title: 'Review', detail: 'confirmed dimensions in parallel' },
    { title: 'Report', detail: 'optional HTML render' },
  ],
}

// opts.agentType was tried and confirmed live against these five agents (all
// established since July/August 2026) before this SKILL.md was finalized: two of
// them (style-reviewer, correctness-reviewer) resolved and ran correctly with no
// registry error. security-deep-review's own Step 4 documents opts.agentType
// THROWING for security-finder/security-verifier — that is a genuine, different
// failure: the registry lags the harness's OWN agent list, so a just-authored
// agents/*.md file is not guaranteed to be in it yet, regardless of how
// established the agent later becomes. These five agents were already registered
// well before this migration, which is why they resolved and security-finder did
// not at the time of its own build. If a future run throws "agent type not found"
// for one of these, that is the same class of registry-lag bug, not a reason to
// doubt this note — fall back to an inline persona for just that dimension.
const AGENT_FOR = {
  secrets: 'secrets-reviewer',
  correctness: 'correctness-reviewer',
  'tests-build': 'tests-build-runner',
  dependencies: 'dependency-reviewer',
  style: 'style-reviewer',
}

// Explicit schemas, not left to the agent's own prose — /tech-blog's migration
// (a later story, NAV-29) live-tested a schema-less pipeline and found the exact
// failure mode this guards against: without a schema, an agent's free-form
// prose (including its own internal reasoning) gets concatenated wholesale into
// whatever consumes the result next, and a script's plain-JS aggregation logic
// (the `results.reduce` below) has nothing to key off if `r.verdict` isn't a
// real, guaranteed field. All 5 dimension agents already document this exact
// verdict+findings shape in their own SKILL.md "Report" sections (see
// agents/*.md) — this schema just makes that a guarantee instead of a norm.
const DIMENSION_SCHEMA = { type: 'object', properties: {
  verdict: { type: 'string', enum: ['PASS', 'WARN', 'BLOCK', 'SKIP'] },
  skip_reason: { type: 'string' },
  findings: { type: 'array', items: { type: 'object', properties: {
    severity: { type: 'string', enum: ['BLOCKER', 'WARNING', 'NIT'] },
    location: { type: 'string' }, what: { type: 'string' }, fix: { type: 'string' },
  } } },
}, required: ['verdict', 'findings'] }
const REPORT_URL_SCHEMA = { type: 'object', properties: {
  url: { type: 'string' },
}, required: ['url'] }

phase('Review')
// `dimension` is zipped onto each result INSIDE the per-task `.then()`, before
// parallel()'s array is ever filtered — an earlier draft attached it afterward by
// indexing DIMENSIONS[i] against the post-filter array, which mislabels every
// result after a dropped one once a falsy/quarantined result compacts the array.
// A live-test correctness review of this very script caught that draft's bug.
const results = (await parallel(DIMENSIONS.map(dim => () =>
  agent(
    `Review this snapshot for the ${dim} dimension.\n\n${snapshot}`,
    { label: `review:${dim}`, phase: 'Review', agentType: AGENT_FOR[dim], schema: DIMENSION_SCHEMA }
  ).then(r => r && { dimension: dim, ...r })
))).filter(Boolean)

// Aggregation is plain logic, not an agent() call — every dimension already
// returns a structured PASS/WARN/BLOCK/SKIP verdict + findings per
// CONVENTIONS.md §4, so rolling up max-severity and building the table is
// arithmetic, not judgment. Spending an LLM call on it would be paying for an
// agent to do what a five-line reduce already does correctly.
//
// SKIP ranks equal to PASS (both dimensions that need no action), so `overall`
// alone can't distinguish "everything passed" from "everything was skipped" — an
// all-SKIP fleet would silently roll up to a bare PASS with no signal in the
// returned object. hasSkips carries that distinction explicitly rather than
// depending on Step 5's prose to notice it after the fact.
const SEVERITY_RANK = { PASS: 0, SKIP: 0, WARN: 1, BLOCK: 2 }
const overall = results.reduce(
  (worst, r) => (SEVERITY_RANK[r.verdict] > SEVERITY_RANK[worst] ? r.verdict : worst),
  'PASS'
)
const hasSkips = results.some(r => r.verdict === 'SKIP')
const aggregated = { results, overall, hasSkips, scope: scopeMeta }

let reportUrl = null
if (wantHtml) {
  phase('Report')
  const rendered = await agent(buildReportPrompt(aggregated), { agentType: 'review-report-writer', schema: REPORT_URL_SCHEMA })
  reportUrl = rendered?.url ?? null
}

return { ...aggregated, reportUrl }
```

The Workflow pipeline's Review phase **spawns `secrets-reviewer`, `correctness-reviewer`,
`tests-build-runner`, `dependency-reviewer`, and `style-reviewer`** — one per confirmed
dimension, via `opts.agentType` (verified against the live registry per the comment
above `AGENT_FOR`) — and, when `wantHtml`, the Report phase **spawns
`review-report-writer`**.

`buildReportPrompt` (constructed in Step 5.5's prose, unchanged from before this
migration) hands `review-report-writer` the same payload it always received: the
verdict and recommendation, per-dimension verdicts (and each `SKIP`'s reason),
every finding with its severity / `file:line` / claim / failure scenario / fix, the
scope and exclusion metadata, the scanner name and version, the fleet size, and the
output directory. It renders; it does not re-review, re-scan, or re-run anything.

Review→Report has no barrier to wait on between them by construction — Report only
runs once Review's `parallel()` has already fully resolved, since aggregation (and
therefore `buildReportPrompt`'s input) needs every dimension's result. This is
identical in shape to `/security-deep-review`'s Verify→Synthesize barrier.

## Step 5 — Print the results, write the artifact

Print the compact table then the recommendation, from the script's return value:

```
Dimension       Verdict   Top findings
─────────────   ───────   ───────────────────────────────────────
Secrets         PASS      gitleaks: clean; semantic: clean
Correctness     BLOCK     off-by-one in pager (src/list.js:42)
Tests / Build   PASS      npm test: 128 passed
Dependencies    WARN      left-pad@^2 floating range (package.json:19)
Style           WARN      leftover console.log (src/api.js:88)
─────────────   ───────
OVERALL: BLOCK — fix the correctness blocker before pushing.
(scope: 12 files, 340 lines · excluded: 2 lockfiles, 1 image · scanner: gitleaks 8.x)
(agents: 4 spawned, 1 skipped — dependencies: no manifest changes)
```

Always report the fleet size and what was skipped, so the cost is visible and a
`SKIP` is never mistaken for a clean pass. If findings remain, offer the scoped
re-run (`CONVENTIONS.md §8`) rather than the full five:

```
To re-check after fixing: /pre-push-review — will re-run correctness + style only.
```

Write the **report artifact** per `CONVENTIONS.md §6` (timestamped, outside the repo
tree or under a gitignored dir, no unmasked secrets) from the script's `results`. If
the script's `hasSkips` is `true` or the review was partial, say so beside the
verdict — PASS-with-gaps ≠ PASS. `hasSkips` is why this is checkable from the
script's return value alone rather than re-deriving it from `results` by hand.

**Exit-code contract** (when run for a hook/CI, `CONVENTIONS.md §5`): PASS/WARN → 0,
BLOCK → non-zero. The suite still advises only — it never runs `git push`.

## Step 5.5 — The HTML report's conditions

The `§6` markdown artifact stays exactly as it is — it is what CI greps and what a
`diff` between two runs reads cleanly. The script's optional Report phase (Step 4)
adds a **sibling `.html`** for the human, because a terminal table scrolls away the
moment the next command runs and a finding with a five-line fix is unreadable in it.

If `reportUrl` came back from the script, **print the `file://` URL** on its own
line, so it is clickable in the terminal:

```
Report: file:///Users/you/.nj-agents-reports/review-20260804T174233Z-e6307dc.html
        (markdown sibling: review-20260804T174233Z-e6307dc.md)
```

Three conditions on `wantHtml`, resolved **before** the script runs (Step 4):

- **`false` when there is nothing to review.** The empty-diff PASS in Step 1 exits
  before any agent is spawned; do not run a Workflow at all to render "nothing
  happened".
- **`false` in CI mode by default** (`CONVENTIONS.md §5`) — a pipeline consumes the
  exit code and the markdown, and nobody opens a browser mid-build. `true` only if
  the caller asks (`--html`), e.g. to attach to a build artifact.
- **A failure in the Report phase never changes `overall`.** If `review-report-writer`
  errors or the directory is unwritable, `reportUrl` stays `null`; say so and fall
  back to the markdown artifact. The review's result is the review's result; a
  rendering problem is not a finding.

This is the one agent that runs *after* Review's `parallel()` fully resolves rather
than alongside the dimensions, so it costs one extra call on top of the fleet stated
in Step 3.5 — mention it there when stating the cost.

## Step 6 — Optional: offer to gate on git push (propose, never silently add)

If no push-gate is wired and the user wants one, *offer* one of these — install only
with explicit, per-project confirmation, never touching global config, never
`--no-verify`:

**Option A — native `.git/hooks/pre-push`** (gates any push by anyone; per-clone,
not committed). A working stub that honors the exit-code contract:

```sh
#!/bin/sh
# nj-agents pre-push gate. Runs the review non-interactively; blocks on BLOCK.
# Bypass is a conscious, visible choice: `git push --no-verify`.
# Requires a non-interactive runner for the suite (e.g. `claude` headless, or your
# CI wrapper) that exits 0 on PASS/WARN and non-zero on BLOCK.
if command -v nj-agents-review >/dev/null 2>&1; then
  NJ_AGENTS_CI=1 nj-agents-review || {
    echo "pre-push-review: BLOCK — push stopped. Fix findings or use --no-verify to override." >&2
    exit 1
  }
fi
exit 0
```

(`nj-agents-review` ships with this toolkit at `bin/nj-agents-review`. It runs this
skill headlessly and maps the verdict onto the §5 exit codes — 0 PASS/WARN, 1 BLOCK,
2 harness error. `claude -p` alone always exits 0, so a hook wired straight to it
would let a BLOCK through. Put `bin/` on PATH, or call it by full path. The hook
degrades to a no-op if it's absent, so it never blocks blindly.)

**Option A is the portable one.** It is a plain git hook running a plain script, so
it gates a push however that push happens — from a terminal, an IDE, or another
agent. The wrapper drives `claude -p` by default and honours `NJ_AGENT_CMD` for a
different CLI:

```bash
NJ_AGENT_CMD="codex exec" nj-agents-review
```

(That override is **not yet verified against a non-Claude runner** — the plumbing
exists, the proof does not. Say so rather than implying it is tested.)

**Option B — project `.claude/settings.json` `PreToolUse` hook** matching
`Bash(git push*)`. **Claude Code only**: `settings.json` and `PreToolUse` are its
own mechanism, with no equivalent in Codex, Cursor or Gemini. It also gates only
pushes made *through Claude* — a push typed into a terminal bypasses it entirely.

Recommend A in almost every case: it is portable, and it catches every push rather
than the subset that goes through one tool. B is worth it only for a solo
Claude-Code workflow where the convenience of an in-session gate outweighs both.
Present the snippet; write it only on the user's go-ahead. Offer to add
`.nj-agents-reports/` to `.gitignore` if the report dir lives under the repo.

## Step 7 — Clean up

Remove scratch/temp files (nothing stays in the repo tree). Leave no hook, config,
or report-dir change behind unless the user opted in (Step 6). Summarize: overall
verdict + exit code, top findings per dimension, anything SKIPped or partially
reviewed that the user should check manually, and where the report was written.

## Running a single dimension

Each dimension is also standalone — `/review-secrets`, `/review-correctness`,
`/review-tests-build`, `/review-dependencies`, `/review-style` — for when you want
just one. Each prints the banner, runs the shared snapshot + hygiene + (where
applicable) secret-gate steps, then spawns its matching agent.
