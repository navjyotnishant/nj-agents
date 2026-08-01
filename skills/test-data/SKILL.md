---
name: test-data
description: "Use this skill when the user asks to \"set up test data\", \"write fixtures for these tests\", \"the tests interfere with each other\", or wants factories and seed data that keep specs independent. Generates fixtures and factories against the repo's own test stack, gives each spec its own data so runs do not collide, and resolves every credential from the environment. Writes only inside detected test directories and PROPOSES the commit. Works in any git repo; nothing here is project-specific."
version: 0.1.0
class: testing
author: navjyotnishant
---

# Test Data (testing)

Generates fixtures and factories so specs get **their own data** and stop interfering
with each other.

> **This is not a nice-to-have.** Test data is the most under-built part of most E2E
> suites and the leading cause of nondeterminism in them. A suite that passes alone
> and fails in parallel, or passes on a fresh database and fails on the second run,
> almost always has a data problem rather than a timing one — and it gets diagnosed
> as flake, quarantined, and eventually deleted. Getting this right is what makes the
> flake ledger meaningful instead of a record of shared-fixture collisions.

This is a **testing-class** skill — follow `CONVENTIONS-testing.md`: `§T1` source
fence, `§T6` propose the commit, `§T8` no credentials in fixtures.

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
| the repo's own test stack | fixture idiom and where they live | **SKIP** — never impose a factory library |
| the app's data model (schema, migrations, ORM models) | generating realistic factories | generate from the case objects alone, and say the shapes are inferred |
| an existing seed or factory setup | extending rather than duplicating | create a new one, and say so |

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  TEST DATA — TESTING                                              ║
╠══════════════════════════════════════════════════════════════════╣
║  Generates fixtures and factories so each spec owns its data and  ║
║  specs stop colliding — the usual cause of "flaky" suites.        ║
║                                                                   ║
║  Credentials come from the environment, never from a file.        ║
║  Writes ONLY inside detected test directories, and PROPOSES the   ║
║  commit — it never runs git.                                      ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **A detected test stack and test root** (`§T5`, `§T1`). None → SKIP.
- **Something to model.** The app's schema/models, or case objects from `/test-plan`.
  Neither → ask rather than inventing a data shape.

## Step 1 — Read what already exists

Before generating anything, find the repo's current approach: existing fixtures,
factories, seed scripts, database helpers, and how specs currently get their data.

**Extend it rather than introducing a second pattern.** Two fixture systems in one
repo is worse than one imperfect system — every spec then has to be read to know
which it uses.

## Step 2 — Make each spec own its data

The core requirement, and the reason this skill exists:

- **Unique per run.** Generate identifying values that cannot collide — a run-scoped
  prefix or a random suffix, not `test@example.com`. Two specs sharing that address
  fail together the moment they run in parallel, and it looks exactly like flake.
- **Created by the spec, not assumed.** A spec that depends on a record some earlier
  spec left behind passes in order and fails in isolation. Every spec sets up what it
  needs.
- **Cleaned up after.** Teardown removes what setup created, so the tenth run behaves
  like the first. Where cleanup is genuinely impossible, say so — a growing database
  is a known cost, not a surprise.
- **No cross-spec ordering.** If spec B needs spec A to have run, that is one spec
  with two phases, not two specs.

> **Shared mutable fixtures are the trap.** A single seeded "test user" that every
> spec logs in as works perfectly until two specs run at once and one changes its
> profile. The failure is intermittent, environment-dependent, and reads as timing —
> so it gets logged as a flake and quarantined, and the real cause survives.

## Step 3 — Credentials from the environment (`§T8`)

Test users, API keys and tokens resolve from env vars. **Never written into a
fixture, factory, page object, or committed config** — whatever the account is worth.

A seeded password in a fixture file is a committed credential. It is also a pattern:
whoever adds the next fixture copies it, and the practice spreads faster than anyone
reviews it.

Where a value must exist for the suite to run, document the **variable name** and
what it needs — never the value.

## Step 4 — Write inside the fence (`§T1`)

Everything lands inside the detected test root. Never application source, never a
production seed script, never a migration.

If the app needs a change to be testable — a seed endpoint, a factory hook, a
test-only route — **report it and stop**. That is application source and this skill is
fenced out of it. "This cannot be seeded cleanly without a change over here" is a
useful finding; making the change quietly is how a test skill starts editing the app.

## Step 5 — Propose the commit (`§T6`)

Diff first, then the exact commands. Never run git.

```bash
git add <the fixture and factory files>
git commit -m "test(<scope>): add factories for <what>"
```

Report format:

```
## Test data — <n> factories, <m> fixtures

Stack:      <detected>       Test root: <path>
Extending:  <existing setup> | new — no existing fixture system found
Modeled on: <schema/migrations> | inferred from case objects

  <factory>     unique per run via <strategy>     cleanup: yes
  <fixture>     unique per run via <strategy>     cleanup: manual — <why>

Credentials: <VAR_NAME>, <VAR_NAME> — read from env, none written to disk

Needs a human change: <e.g. no seed endpoint; app source, outside §T1>
Not cleaned up: <what persists between runs, and why>

Nothing was committed. Commands above are yours to run.
```

**Say what persists.** Data that survives a run is the thing that makes run eleven
behave differently from run one, and a reader needs to know it exists.

## Safety rails

- **Writes only inside detected test directories** (`§T1`). Never app source, never a
  production seed or migration. If the fix belongs outside, report and stop.
- **Never writes a credential** to disk (`§T8`) — env vars, and document the name
  only.
- **Never introduces a second fixture system** where one exists — extend it.
- **Never generates a shared mutable fixture** that specs contend over. Unique per
  run, created by the spec, cleaned up after.
- **Never runs git** (`§T6`) — diff plus commands.
- **Never installs a factory library** (`§T5`). None detected → SKIP.
- **A harness error is not a pass** (`CONVENTIONS.md §5`).
