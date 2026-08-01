---
name: test-author
description: "Use this skill when the user asks to \"write the e2e tests for this\", \"generate specs from the test plan\", \"scaffold page objects\", or wants test specs written against the repo's own runner. Consumes /test-plan's case objects, emits specs for whatever framework the repo already uses (never a hardcoded one), enforces a data-testid locator contract and flags brittle selectors, and generates page objects from the detected app structure. Writes only inside detected test directories and PROPOSES the commit — it never runs git. Works in any git repo; nothing here is project-specific."
version: 0.1.0
class: testing
author: navjyotnishant
---

# Test Author (testing)

Turns `/test-plan`'s case objects into specs, in whatever framework the repo already
uses.

**Keep spec generation dumb and templated.** The intelligence belongs upstream: which
cases to write is `/test-plan`'s judgement, and re-deriving it here produces two
opinions that disagree. This skill's job is a faithful, boring translation from case
object to runnable spec.

This is the first skill in the class that **writes into the repo**, so `§T1` and `§T6`
are not background rules here — they are the shape of the skill.

This is a **testing-class** skill — follow `CONVENTIONS-testing.md`: `§T1` source
fence, `§T2` never weaken an assertion, `§T5` detect never install, `§T6` propose the
commit, `§T8` no credentials in fixtures.

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

## Dependencies

Detected at runtime, never installed by this skill (`§T5`).

| Tool | Used for | Without it |
|---|---|---|
| the repo's own test framework | knowing what a spec looks like here | **SKIP** — never scaffold a framework, never pick one |
| `/test-plan` output | the cases to write | ask for cases; do not invent a plan from the codebase |
| the app's markup or component source | deriving page objects and locators | generate specs without page objects, and say so |

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  TEST AUTHOR — TESTING                                            ║
╠══════════════════════════════════════════════════════════════════╣
║  Generates specs from /test-plan's cases, in YOUR repo's own      ║
║  framework — never one it picks. Enforces a data-testid locator   ║
║  contract and flags brittle selectors.                            ║
║                                                                   ║
║  Writes ONLY inside detected test directories, never app source.  ║
║  Shows the diff and PROPOSES the commit — it never runs git.      ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **Case objects** from `/test-plan` (via the run manifest, `§T13`). Absent → ask.
- **A detected test framework** (`§T5`). None → SKIP; this skill does not choose one.
- **A detected test directory** (`§T1`). None → SKIP rather than creating a layout.

## Step 1 — Detect the framework and the test root (`§T5`, `§T1`)

Probe for what the repo uses: config files, `package.json` scripts and devDeps, the
existing spec layout, a documented command. **Read an existing spec** — house style,
import conventions, how they structure setup — and match it. A generated spec that
does not look like its neighbours will be rewritten by the first person to touch it.

Resolve the test root the same way. Everything this skill writes goes inside it, and
nowhere else.

**Nothing detected → SKIP with the reason.** Never install a framework, never
scaffold a config, never pick one because the repo "looks like" it should use it.

## Step 2 — Enforce the locator contract

Selectors are why generated suites rot. A spec keyed to markup structure breaks on a
refactor that changed nothing a user can see, and the resulting red build teaches
people to distrust the suite.

- **Prefer `data-testid`** (or the repo's existing equivalent — detect it, do not
  impose this one).
- **Flag brittle selectors** and say why: `nth-child` and positional CSS break on
  reordering; text matching breaks on copy edits and i18n; XPath breaks on almost
  anything.
- **If the app has no testids**, say so plainly and propose adding them **as a
  separate, human-owned change**. Do not add them yourself: that is application
  source, and `§T1` fences this skill out of it. A spec that reaches into markup
  because the testids are missing is a worse outcome than a report saying they are
  missing.

## Step 3 — Generate specs and page objects

One spec per case object, carrying its `id` so the traceability matrix in
`/test-report` can link requirement → case → spec → result.

Page objects derive from the detected app structure. Keep them thin — a page object
that grows assertions is a second place where test logic hides.

**Assertions come from the case's `expected` field.** Do not soften one to make a
generated spec pass on first run: a spec that passes because its assertion is weak is
worse than no spec, and `§T2` forbids it for exactly this reason. If a case cannot be
expressed against the current app, say so and skip it — that is a finding.

Credentials and test users resolve **from the environment** (`§T8`). Never write one
into a spec, a fixture, or a page object, whatever the account is worth. A seeded
password in a committed file is a committed credential, and it gets copied by whoever
reads it as the house pattern.

## Step 4 — Write inside the fence (`§T1`)

Every file lands inside the detected test root. Never application source, never CI
config, never a shared util outside the test tree.

If the right place for something is outside that fence — a testid in a component, a
seed script in the app — **report it and stop**. That is a real finding: "this cannot
be tested cleanly without a change over here" is useful information, and quietly
making the change is how a test skill starts editing the application.

## Step 5 — Propose the commit (`§T6`)

Show the **diff**, then the exact commands. Never run git.

```bash
git add <the spec and page-object files>
git commit -m "test(<scope>): add e2e coverage for <requirement>"
```

Generated specs are code that will gate other people's pushes. That earns a read
before it lands — which is the whole reason this class proposes rather than commits.

Report format:

```
## Specs generated — <n> from <m> cases

Framework:  <detected> (matched style from <existing spec>)
Test root:  <path>          Locators: data-testid | <repo's own convention>

  <spec file>                  cases: <ids>
  <page object>                derived from <source>

Brittle selectors flagged: <n>
  <file:line>  nth-child(3) — breaks on reordering; needs a testid

Not generated: <case ids that could not be expressed, and why>
Needs a human change: <testids missing in <component> — app source, outside §T1>

Nothing was committed. Commands above are yours to run.
```

## Safety rails

- **Writes only inside detected test directories** (`§T1`). Never app source, never
  CI config. If the fix belongs outside, report and stop.
- **Never weakens an assertion to make a spec pass** (`§T2`). A case that cannot be
  expressed is skipped and reported, not softened.
- **Never installs or picks a framework** (`§T5`). None detected → SKIP.
- **Never writes a credential** into a spec, fixture, or page object (`§T8`) — env
  only.
- **Never runs git** (`§T6`) — diff plus commands, always.
- **Never adds testids to application source.** Propose them; the human owns that
  change.
- **A harness error is not a pass** (`CONVENTIONS.md §5`).
