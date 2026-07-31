# nj-agents — shared testing conventions

The **testing class** of skills is a fifth class alongside review (`CONVENTIONS.md`),
authoring (`CONVENTIONS-authoring.md`), workflow, and PM (`CONVENTIONS-pm.md`). It
exists because of blast radius, not taxonomy:

| Class | Writes | Runs |
|---|---|---|
| review | nothing | the repo's own test/lint/build |
| authoring | a docs artifact | nothing |
| workflow | a PR draft | nothing |
| pm | a tracker object | nothing |
| **testing** | **test source into the repo** | **that source, against a running app** |

No existing class does either. `/review-tests-build` runs commands but writes
nothing; `/test-gap-finder` reads coverage and explicitly never writes a test. A skill
that generates a spec and then executes it against a live application is a different
kind of thing, and squeezing it into the authoring class would mean inheriting
placement rules written for a changelog.

That combination is also why this doc is mostly prohibitions. A test suite that can
edit itself and run itself has two failure modes nobody notices until much later: it
goes green by weakening its own assertions, and it publishes a live credential it
captured from a real session. **T2 and T4 exist for exactly those two.**

The one rule the whole suite shares still holds: **the human decides.** Testing skills
propose specs and repairs; they never commit them.

> **Enforced, not merely stated.** `check.sh`'s `check_class_contract` has a `testing)`
> branch asserting **T1**, **T2** and **T3** from each skill's own text. A skill that
> quietly omits one is a finding, not a style preference — the `social` class is the
> cautionary case, having shipped with a contract that lived only in prose.

---

## Also applies

`CONVENTIONS-orchestration.md` **§U** binds every skill regardless of class — ground
everything in the repo, never run git on your own initiative, no secrets in output,
keep `CHANGELOG.md` current when the change is user-facing, degrade rather than fail,
and say what you did not do. The clauses below are what this class adds on top.

---

## §T1 — Source fence (shared; enforced)

A testing skill writes **only inside detected test directories**. Never application
source, never config outside the test tree, never CI definitions.

Detect the test root at runtime the way `/review-tests-build` detects commands —
`tests/`, `e2e/`, `spec/`, `__tests__/`, `cypress/`, `playwright/`, or whatever the
repo's own config points at. Do not assume a layout.

**If the correct fix is in application code, report it and stop.** That is a real,
useful outcome: "this test is right and the app is wrong" is the finding. Editing the
app to make a test pass inverts the entire point of the suite.

A skill that legitimately writes nothing — `/test-plan`, `/test-report` — satisfies
this by **saying it is read-only**. Never by omission: an unstated fence is
indistinguishable from a missing one, and the check treats it that way.

---

## §T2 — Repair constraints (shared; enforced)

The clause that keeps the suite honest. A repair **may**:

- fix a selector that no longer matches
- replace a brittle wait with a proper condition
- correct setup and teardown
- fix a genuinely wrong fixture or its wiring

A repair **may not**:

- weaken or delete an assertion
- add a fixed `sleep`
- raise a retry count
- add a `skip`, `.only`, `xit`, or any other suppression

**Anything touching an assertion escalates to human review** rather than appearing in
a proposed diff.

> **Why this is absolute.** A self-healing test agent with soft constraints converges
> on green-by-deletion, and nobody notices for two months because the suite is
> passing. A weakened assertion looks identical to a fixed test from the outside —
> the only signal is the diff, and the diff is exactly what stops being read once
> the suite is "reliable". The constraint has to hold when it is inconvenient, or
> it does not hold.

---

## §T3 — Environment gate (shared; enforced)

Any skill that executes tests against a running application requires an **explicit
non-prod base URL**. Missing or prod-looking → **BLOCK**.

This is the only clause whose blast radius is outside the repo, so it is mechanical
rather than judged. Two skills disagreeing about `https://staging.acme.com` would
make the gate advisory, which is the same as not having one.

**Allow** — an explicit opt-in (env var or config) always wins, plus:

| Form | Example |
|---|---|
| loopback | `localhost`, `127.0.0.1`, `::1` |
| reserved TLD | `*.local`, `*.test`, `*.localhost` |
| private range | `10.x`, `172.16–31.x`, `192.168.x` |
| labelled non-prod | first label contains `dev`, `test`, `staging`, `qa`, `preview`, `sandbox` |

**BLOCK** — everything else. A bare apex domain, `www.*`, anything with a `prod` or
`live` label, and **anything unrecognised**.

> **Unrecognised is BLOCK, never allow.** A URL nobody anticipated is precisely the
> case to stop on. The failure mode has to be safe: refusing to run against a URL
> that turns out to be staging costs one env var; running against one that turns out
> to be production costs considerably more.

Always **say which rule matched**. A false BLOCK should be one env var away from
fixed, not a mystery.

---

## §T4 — Artifact containment (shared)

Raw artifacts — Playwright trace, HAR, video, screenshots — **stay in the gitignored
temp dir**. They are never attached to a ticket, uploaded, or committed. Any attempt
to export one **BLOCKs**, and says where to view it locally instead
(`playwright show-trace <path>`) so the block is a redirect rather than a dead end.

Text **derived** from an artifact and published into a report, ticket body, or run log
— failure messages, request URLs, assertion diffs — passes a **secret-pattern scrub**
first. Prefer the scanner `/review-secrets` already requires (`gitleaks` /
`trufflehog` / `detect-secrets`) over inventing a second pattern set; this repo has a
standing rule against heuristic-only secret detection.

> **Containment, not redaction — and the distinction is deliberate.** An earlier draft
> of this clause required redacting traces and HARs before export. That means scrubbing
> `Authorization`, `Set-Cookie` and request bodies out of a zip and a JSON blob, then
> *proving coverage* the way `screenshot-redactor` does — a large security-critical
> surface where a miss leaks a live credential, built for a use case nobody has asked
> for. A developer reproducing locally already has full fidelity with nothing published.
>
> **But "artifacts stay local" does not mean nothing is published.** `/test-triage`
> publishes derived text on day one. A bearer token in a query string, or a session ID
> in an error message, travels out through a ticket body with no HAR ever moving. That
> is why the scrub is not optional even though the redactor is deferred.
>
> Full artifact redaction is the **unlock condition for export**, and is out of scope
> until someone actually needs a HAR on a ticket.

**Known limit, state it in the docs:** a repo whose CI runs `actions/upload-artifact`
on `playwright-report` is exporting artifacts *outside this skill's control*. This
clause governs what the skill does, not what the surrounding pipeline does.

---

## §T5 — Detect, never install (shared)

Inherited from `/review-tests-build`. Detect the repo's own runner, config and
commands at runtime. **No framework is hardcoded anywhere** — not Playwright, not
Cypress, not Vitest.

Nothing detected → **SKIP with a labeled reason**, never a silent pass and never an
install. "No E2E runner detected — skipping" is a useful report; installing Playwright
into someone's repo to have something to run is not.

---

## §T6 — Propose the commit (shared)

Generated specs and repairs are shown as a **diff plus the exact git commands**. The
skill never runs git.

This is `CONVENTIONS-authoring.md §A3` applied to test source. The reason is sharper
here: a generated spec is code that will gate other people's pushes, so it earns a
read before it lands.

---

## §T7 — Budget (shared)

Every loop declares a bound: max repair iterations, max wall clock. Exhaustion
reports **WARN with what was tried** — never a silent give-up, never an unbounded
retry.

A repair loop that quietly stops looks identical to one that succeeded. Say which.

---

## §T8 — No credentials in fixtures (shared)

Test users, API keys and tokens resolve **from the environment**. Never written into
a fixture, a factory, a page object, or a committed config.

A seeded test password in a fixture file is a committed credential, whatever the
account is worth — and it will be copied into the next fixture by whoever reads it
as the house pattern.

---

## §T9 — Model-agnostic authoring (shared; partly enforced)

Skill and agent instructions name **no model, vendor, or product**. They declare the
**capabilities** they require — tool use, file read/write, structured output,
multi-step planning — rather than assuming a model family, context window, tokenizer,
or reasoning mode, and they avoid provider-specific prompt idioms.

**Deterministic logic lives in scripts, not in instructions.** A URL-safety rule
(§T3) or a secret scrub (§T4) written as a prompt drifts when the model changes;
written as a script it does not. If the outcome must be identical every run, it does
not belong in a model instruction.

**Every agent output is schema-validated**, so any model's output is checkable the
same way and a malformed response is a caught error rather than a silently wrong
verdict.

Where a required capability is unavailable, **degrade with a labeled reason** rather
than assuming it.

> **Half of this is already a gate.** `check.sh`'s `check_vendor_neutral` fails an
> agent that pins `model:`, a skill that names a vendor in a user-facing claim, and a
> skill that recommends a model to run on — across the whole suite, not just this
> class. What this clause adds on top is the schema validation and the
> capability-declaration discipline.

---

## §T10 — Cost harness (shared)

Every run accounts for its own spend: tokens and tool calls **per skill and per
agent**, wall clock per phase, written into the run manifest and surfaced in the
report.

Budgets are expressed in **cost as well as time** (extending §T7). Exceeding one
reports **WARN with the breakdown** — not a silent failure, not an indefinite
continuation.

Fixture runs carry a **cost baseline**, so a change that doubles spend shows up as a
regression in CI rather than as a surprise invoice.

---

## §T11 — Parallel execution (shared)

Independent work fans out rather than running in sequence: spec shards, per-failure
triage, per-spec repair attempts.

- Fan-out respects a **configurable concurrency cap**.
- It **joins on a barrier**, and **schema-validates every subagent output** before the
  reduce step (§T9).
- **Aggregation order is deterministic and independent of completion order.** The same
  inputs must always produce the same verdict — a gate whose result depends on which
  subagent finished first is not a gate.
- A subagent failure is **reported and quarantined**, never allowed to silently shrink
  the result set. Four of five shards passing is not a pass.

---

## §T12 — Progress and logging (shared)

Every run writes a **structured, append-only log** alongside the report artifact: one
record per phase transition, subagent spawn and join, verdict, and budget event.

Progress is emitted at **phase boundaries**, and phases that can run long emit
**heartbeats** — a stalled run must be distinguishable from a slow one.

Logs are **published text**, so they pass §T4's derived-text scrub and contain no
unmasked credentials. They are not artifacts, so the export prohibition does not apply
to them; the scrub does.

In CI mode the log is **machine-readable**.

---

## §T13 — The run manifest (shared)

Testing skills **do not pass state to each other directly.** Each writes to, and reads
from, a single **run manifest** — a JSON file under the run's temp dir.

That indirection is the point: `/test-triage` consumes what `/e2e-run` recorded rather
than being invoked by it, so each skill is independently runnable and independently
testable. A skill that only works when called by another skill cannot be verified on
its own, and the whole class becomes one untestable pipeline.

Minimum fields:

| Field | Why |
|---|---|
| `run_id` | correlates manifest, log and artifacts |
| `commit` | the SHA under test — triage correlates failures to it |
| `environment` | the resolved base URL and which §T3 rule allowed it |
| `scope` | which specs/shards this run covered |
| `artifacts_dir` | absolute path in the temp dir (§T4 — never exported) |
| `verdicts` | per dimension, plus the aggregate |
| `cost` | tokens and tool calls per skill and per agent, wall clock per phase (§T10) |
| `subagents` | spawn/join records and the concurrency cap in force (§T11) |
| `log` | pointer to the structured phase log (§T12) |

Cost, subagent and log fields live **here**, not in each skill. They are cross-cutting,
and an umbrella can only report them uniformly if they are recorded uniformly.

The manifest is **run state, not history** — it lives and dies with the temp dir.
Anything that must outlive the run goes in the ledger below.

---

## §T14 — The flake ledger (shared)

Per-spec failure history: fail rate over the last N runs, per spec and assertion, plus
quarantine state. This is what lets `/test-triage` say *"this spec fails 30% of the
time regardless of the diff"* instead of guessing.

**It is committed, at `.nj-agents/flake-ledger.json`.** Not gitignored, not under
`.nj-agents-reports/`.

> **Why committed, when every other artifact in this repo is not.** Report artifacts
> are the output of one run — disposable by design, and `.nj-agents-reports/` is
> gitignored accordingly. The ledger is the opposite: it is **only useful as
> accumulated history**, and its value is proportional to how many runs it has seen.
>
> Gitignored, it starts **empty on every CI runner** — and CI is exactly where flake
> detection matters most, because that is where the same spec fails intermittently
> across a hundred runs nobody is watching. A ledger that resets each run cannot
> distinguish a flake from a regression, which is the one thing it exists to do.
>
> Committed, it is also **reviewable in a PR**: a quarantine proposal shows up as a
> diff someone approves, rather than a state change in a file nobody sees. Given
> quarantine removes a spec from the gate, that visibility is a feature.
>
> The cost is a committed data file that changes on most runs. That is real churn, and
> it is the honest price of the above. Mitigations: write it **only when a value
> actually changes**, keep it sorted and one-record-per-line so diffs are readable,
> and never store anything from an artifact in it — spec identity, counts and dates
> only, so §T4's scrub has nothing to do here.

**Ledger records survive a rename.** A spec that moves or is renamed keeps its
history — key on a stable identifier plus a path fallback, not the path alone.
Otherwise every refactor silently resets the flake data and a chronically unstable
spec gets a clean slate it did not earn.

**Quarantine is never silent.** A proposal carries an SLA and opens a tracking issue.
A spec removed from the gate with no owner and no date is a spec deleted slowly.

---

## Spawning subagents

Skills in this class fan out by design, so `CONVENTIONS-orchestration.md` applies in
full: **§C** (state the cost shape before spawning, cap fix rounds at 2, halt on any
signal to stop) and **§R** (announce the roster before dispatch, mark each agent as it
lands). §T10 and §T11 extend those with cost accounting and determinism requirements
specific to a test run.

---

## The verdict contract

An umbrella in this class (`/e2e-suite`) aggregates **PASS / WARN / BLOCK** the way
`/pre-push-review` does, and honours the same exit codes from `CONVENTIONS.md §5`:
`0` PASS or WARN, `1` BLOCK, `2` harness error.

**A harness error is never a pass.** A run that could not reach a verdict — the app
never came up, the runner was not detected, the budget ran out — exits 2. Silence
must not read as approval; that is the whole reason the exit-code contract exists.
