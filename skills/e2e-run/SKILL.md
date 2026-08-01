---
name: e2e-run
description: "Use this skill when the user asks to \"run the e2e tests\", \"run the browser tests\", \"execute the end-to-end suite\", or wants the repo's own E2E suite run with full failure evidence captured. Detects the repo's E2E runner at runtime (Playwright, Cypress, WebdriverIO, or whatever its config points at), BLOCKs unless an explicit non-prod base URL is given, runs the suite, and captures trace, HAR, video and console into a gitignored temp dir. Raw artifacts never leave that dir; anything published is scrubbed first. Works in any git repo; nothing here is project-specific."
version: 0.2.0
class: testing
author: navjyotnishant
---

# E2E Run (testing)

Runs the repository's **own** end-to-end suite and captures enough evidence to
diagnose a failure without anyone re-running it by hand. It detects the runner,
refuses to execute against anything that looks like production, and keeps every raw
artifact inside a gitignored temp directory.

It is the **evidence-gathering** half of the testing class. It does not decide what a
failure means — that is `/test-triage`, which reads the run manifest this skill
writes. Keeping those apart is deliberate (`§T13`): a skill that can only run as part
of a pipeline cannot be verified on its own.

This is a **testing-class** skill — follow `CONVENTIONS-testing.md`. The clauses that
bind this one hardest: `§T1` source fence, `§T3` environment gate, `§T4` artifact
containment, `§T5` detect-never-install, `§T13` run manifest.

> **Finding the conventions file.** It lives at the toolkit repo root, two levels
> above this skill — not beside `SKILL.md`. Skills are usually installed as
> symlinks into your runner's skills directory, so a plain relative path resolves
> against the *link* and misses it. Resolve the link first:
>
> ```bash
> ROOT="$(dirname "$(readlink -f "<this skill's base directory>")")/.."
> ```
>
> then read `$ROOT/CONVENTIONS-testing.md` and `$ROOT/CONVENTIONS.md`. If a file is
> genuinely absent, say so and continue with the procedure below rather than stopping.

> **Every skill follows `CONVENTIONS-orchestration.md` §U** — ground everything in
> the actual repo, never run git on your own initiative, no secrets in output,
> keep `CHANGELOG.md` current when the change is user-facing, degrade rather than
> fail, and say what you did not do.

**This skill writes nothing into the repo.** It writes only into a temp dir outside
the repo tree, so `§T1`'s source fence is satisfied trivially — there is no path on
which it edits a spec or an application file. It runs code; it does not author it.

## Dependencies

Detected at runtime, never installed by this skill (`§T5`).

| Tool | Used for | Without it |
|---|---|---|
| the repo's own E2E runner | running the suite | **SKIP** with a labeled reason — never installed, never substituted |
| the runner's trace/video flags | capturing evidence | run anyway, report which evidence was unavailable |
| `gitleaks` *or* `trufflehog` *or* `detect-secrets` | scrubbing published text (`§T4`) | **BLOCK** before publishing anything — no heuristic-only fallback |

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  E2E RUN — TESTING                                                ║
╠══════════════════════════════════════════════════════════════════╣
║  Runs THIS REPO'S own E2E suite against a base URL you supply.    ║
║  It BLOCKS unless that URL is explicitly non-production.          ║
║                                                                   ║
║  Trace, HAR, video and console are captured into a gitignored     ║
║  temp dir. Raw artifacts NEVER leave it — not to a ticket, not    ║
║  to a commit. Text published from them is secret-scrubbed first.  ║
║                                                                   ║
║  It runs your tests; it never writes or edits them.               ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **An E2E runner in the repo.** Detected, never installed (`§T5`). None → SKIP.
- **An explicit non-prod base URL** (`§T3`). Missing → BLOCK; this is not inferred.
- **No API key / no network for the analysis itself.** The suite talks to your app;
  this skill talks to nothing else.

## Step 1 — Resolve the base URL and gate on it (`§T3`) — BEFORE anything else

Do this **first**, before detecting a runner or reading a config. Everything after
this step costs time and touches an application; there is no point spending either if
the target is wrong.

Take the URL from an explicit argument, then `NJ_E2E_BASE_URL`, then the repo's own
test config. **Never infer one, and never default to whatever the config happens to
hold** — a config committed for a CI environment can point anywhere.

Apply `§T3`'s rules exactly as written there. In short: an explicit opt-in wins;
loopback, reserved TLDs, private ranges and a `dev`/`test`/`staging`/`qa`/`preview`/
`sandbox` first label are allowed; **everything else BLOCKs, including anything
unrecognised**.

**Always say which rule matched.** A false BLOCK should be one env var away from
fixed:

```
BLOCK — refusing to run against https://acme.com
  rule: apex domain with no non-prod label
  allow it explicitly with NJ_E2E_BASE_URL, or point at your staging host
```

## Step 2 — Detect the runner (`§T5`)

Discover what this repo actually uses. Probe, do not assume:

- a config file — `playwright.config.*`, `cypress.config.*`, `wdio.conf.*`,
  `codecept.conf.*`, or a framework key in `package.json`
- a script — an `e2e`, `test:e2e`, `integration` or similar entry in `package.json`,
  `Makefile`, `justfile`, `Taskfile`
- a documented command in `CLAUDE.md` / `AGENTS.md` / `README`
- the directory layout — `e2e/`, `tests/e2e/`, `cypress/`, `playwright/`

**Nothing detected → SKIP with the reason**, and say what was probed. Never install a
runner, never scaffold a config, never substitute a different framework. "No E2E
runner detected" is a useful report; installing Playwright into someone's repo so
there is something to run is not.

Prefer the repo's **own script** (`npm run test:e2e`) over a reconstructed command —
it carries flags and env the raw binary invocation would lose.

## Step 3 — Run, capturing evidence into a temp dir (`§T4`)

Create a run directory **outside the repo tree** — the scratchpad or `mktemp -d`,
never `.nj-agents-reports/` and never a path inside the working copy. Record it as
`artifacts_dir` in the manifest.

Enable whatever evidence the detected runner supports — trace, HAR, video, console —
using **that runner's own flags**. Do not hand-roll capture. If a flag is unavailable,
run without it and record which evidence is missing rather than failing the run.

Keep the runner's own exit code. A suite that fails is a *result*, not an error: this
skill exits non-zero only when it could not produce one (`CONVENTIONS.md §5`).

**A long run must not look like a hung one** (`§T12`): emit progress at phase
boundaries, and a heartbeat while the suite runs.

## Step 4 — Write the run manifest (`§T13`)

Everything downstream reads this, and nothing downstream is called from here. Write
at minimum: `run_id`, `commit`, `environment` (the resolved URL **and which `§T3` rule
allowed it**), `scope`, `artifacts_dir`, per-spec results, `cost`, and the `log`
pointer.

Recording the matching rule matters more than it looks: a triage six hours later that
cannot tell which environment produced a failure is guessing.

## Step 5 — Report, scrubbing anything published (`§T4`)

Two different rules, and conflating them is the mistake to avoid:

**Raw artifacts stay put.** Trace, HAR, video and screenshots never leave the temp
dir — not attached to a ticket, not copied into the repo, not uploaded. An attempt to
export one **BLOCKs**, and the block names the local viewer so it redirects rather
than dead-ends:

```
trace: /tmp/nj-e2e-4f2a/trace.zip
  view it with:  npx playwright show-trace /tmp/nj-e2e-4f2a/trace.zip
  (not attached — raw artifacts do not leave the temp dir, §T4)
```

**Published text gets scrubbed.** Failure messages, request URLs and assertion diffs
in the report pass the secret scrub first. A bearer token in a query string or a
session ID in an error message travels out through a report with no artifact ever
moving — that is the leak this catches, and it is why the scrub is not optional even
though the raw artifacts never move.

What the scrub covers, at minimum:

| Pattern | Example | Published as |
|---|---|---|
| `Authorization` header values | `Authorization: Bearer eyJ…` | `Authorization: Bearer ***` |
| session and auth cookies | `Set-Cookie: sid=abc123` | `Set-Cookie: sid=***` |
| credentials in a URL | `https://user:pw@host/…` | `https://***@host/…` |
| token-ish query params | `?token=`, `?sig=`, `?key=`, `?access_token=` | value masked |
| vendor-prefixed keys | `sk-…`, `ghp_…`, `AKIA…` | masked |

**Strip the query string entirely unless it is provably credential-free.** Query
strings are the common leak and are rarely load-bearing for diagnosing a failure —
`GET /api/orders?token=***` tells you as much as the original did.

**Use the scanner the repo already requires** (`gitleaks` / `trufflehog` /
`detect-secrets`) rather than inventing a second pattern set. This repo has a
standing rule against heuristic-only secret detection, and two pattern sets means two
things to keep correct. Where the scanner is impractical for a short string, say
which fallback matched rather than scrubbing silently.

Mask, do not delete: `Bearer ***` tells a reader an auth header was present, which is
often the diagnostic detail. An absent line tells them nothing.

Report format:

```
## E2E run — <N> specs, <P> passed, <F> failed

Runner:      <detected runner + how it was found>
Environment: <base URL>  (allowed by: <the §T3 rule>)
Evidence:    trace ✓  HAR ✓  video —  console ✓     (— = unsupported by this runner)
Artifacts:   <temp path — local only, not exported>
Manifest:    <path>

Failures:
  <spec> — <scrubbed failure message>

Verdict: PASS | WARN | BLOCK
Next:    /test-triage reads the manifest to classify these
```

Say plainly what was **not** done: evidence the runner could not capture, specs
skipped, a partial run. A silent gap reads as a clean result.

## Step 6 — CI mode, exit codes, and the report artifact

**Detect CI mode** the same way the review class does (`CONVENTIONS.md §5`):
`NJ_AGENTS_CI=1`, a `--ci` argument, or the user saying it is for a pipeline. In CI
mode: never prompt, and resolve ambiguity to the safe outcome rather than guessing.

**Write the report** to `${NJ_AGENTS_REPORT_DIR:-<repo>/.nj-agents-reports}/`,
timestamped. That directory is gitignored — the report is a record of a run, not a
repo artifact, and `§T1` still holds.

> Note the two directories are different and the difference matters. The **report**
> goes to `NJ_AGENTS_REPORT_DIR` and is scrubbed text a human reads. The **raw
> artifacts** — trace, HAR, video — stay in the run's temp dir and never move
> (`§T4`). Writing a trace into the report dir would be an export, and the report
> dir is inside the repo tree.

**Exit codes** (`CONVENTIONS.md §5`):

| Code | When |
|---|---|
| `0` | PASS or WARN — the suite ran and produced a result, pass or fail |
| `1` | BLOCK — the `§T3` gate refused, or a secret scan hit |
| `2` | harness error — no verdict was reached |

**A failing suite is exit 0.** This skill reports what the suite did; it does not
decide whether failures should stop a pipeline. That is `/e2e-suite`'s job, and
conflating the two means a red suite and a broken runner become indistinguishable to
a caller.

**No runner detected is exit 0 too** — a SKIP with a labeled reason is a successful
run of a skill that correctly found nothing to do (`§U`). Reserve exit 2 for the case
where the skill genuinely could not tell you anything.

## Safety rails

- **BLOCK on a missing or prod-looking base URL** (`§T3`). Unrecognised is BLOCK,
  never allow. This gate runs before anything else.
- **Raw artifacts never leave the temp dir** (`§T4`). Any export attempt BLOCKs.
- **Scrub every published string** (`§T4`) — the artifact staying put does not stop a
  token reaching a report.
- **Writes nothing into the repo** (`§T1`). It runs tests; it never authors or edits
  them. No spec is created, modified, skipped, or deleted — including to make a run
  green (`§T2` — this skill has no repair path at all).
- **Detect, never install** (`§T5`). Nothing detected → SKIP with a labeled reason.
- **Never `--no-verify`, never bypass a gate.**
- **A harness error is not a pass** (`CONVENTIONS.md §5`): if no verdict was reached,
  exit 2.
- Clean up the temp dir on exit; a crashed run leaves nothing in the repo tree.
