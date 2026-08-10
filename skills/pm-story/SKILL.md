---
name: pm-story
description: Use this skill when the user asks to "write a user story", "create a story in Linear/Jira", "draft a story for this feature", or wants a well-formed Story issue. Drafts one industry-standard INVEST user story ("As a … I want … so that …") with Gherkin (Given/When/Then) acceptance criteria per the Scrum Guide and an estimate hint, then — on opt-in — creates it in whatever PM tracker is connected via MCP (Linear/Jira/Notion/GitHub Issues), else hands you paste-ready markdown. Never bulk-creates; grounds scope in your intent, never invents. Optional parent Epic link. Works with any connected tracker; nothing here is project-specific.
version: 0.1.0
class: pm
author: navjyotnishant
---

# PM Story (PM-authoring)

Drafts one well-formed **user Story** and, on opt-in, creates it in the connected PM
tracker. A leaf skill of the **PM-authoring class** — follow `CONVENTIONS-pm.md`
(§P0 standards, §P1 ground, §P2 neutral-model→per-tracker map, §P3 propose-the-create,
§P4 tracker idempotence, §P6 MCP-detect-never-require, §P7 safety, §P8 report-the-tree).

> **Standards-grounded, not house style.** The story follows **INVEST** (Wake) and the
> **Scrum Guide** — a proper "As a / I want / so that" sentence, **Gherkin
> (Given/When/Then)** acceptance criteria that double as the story's Definition of Done.
> See `CONVENTIONS-pm.md §P0` for the full field set and its sources. You get a story a
> CSM/PSM-trained team would accept into a sprint, on whatever tracker you use.

> **Finding the conventions file.** It lives at the toolkit repo root, two levels
> above this skill — not beside `SKILL.md`. Skills are usually installed as
> symlinks into your runner's skills directory, so a plain relative path resolves against the
> *link* and misses it. Resolve the link first:
>
> ```bash
> ROOT="$(dirname "$(readlink -f "<this skill's base directory>")")/.."
> ```
>
> then read `$ROOT/CONVENTIONS-pm.md`. If a file is genuinely absent, say so and continue
> with the procedure below rather than stopping.

> **Every skill follows `CONVENTIONS-orchestration.md` §U** — ground everything in
> the actual repo, never run git on your own initiative, no secrets in output,
> keep `CHANGELOG.md` current when the change is user-facing, degrade rather than
> fail, and say what you did not do.

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  PM-STORY — PM-AUTHORING                                          ║
╠══════════════════════════════════════════════════════════════════╣
║  Drafts one INVEST user story + acceptance criteria, then (on     ║
║  opt-in) creates it in your connected tracker — else hands you    ║
║  paste-ready markdown. Never bulk-creates; scope is grounded in   ║
║  your intent, never invented.                                     ║
╚══════════════════════════════════════════════════════════════════╝
```

## Step 1 — Ground the story (§P1)

Gather from the user's intent (the primary source) and light repo context when the
story is about this codebase:
- **Who** the user/persona is, **what** they want, **why** (the value).
- The area of the system touched, so acceptance criteria are concrete.

Invent no scope (§P7). If a detail isn't known, mark it `TBD` or ask — never fabricate
a requirement.

## Step 2 — Draft into the neutral issue model (§P2)

Fill the neutral model with `type: story`, covering the **full §P0 story field set** so
the item is standard-complete (mark a genuinely unknown field `TBD`, never drop it):

- **title** — a short capability, not a task ("Cursor-based pagination on search").
- **description** — the story sentence: **"As a `<persona>`, I want `<capability>`, so
  that `<value>`."** Plus any context/constraints from Step 1.
- **acceptance_criteria** — concrete, checkable, in **Gherkin (Given/When/Then)** or
  bullet form. The heart of the story and its Definition of Done; don't ship a story
  without it.
- **non-functional constraints** — perf/security/a11y where they apply (§P0 optional).
- **parent** — the Epic ID if the user names one (optional).
- **labels / estimate / priority / dependencies** — only if the user supplies, the
  tracker needs them, or they sharpen scope.
- **recommended_model** — apply the §P2a complexity heuristic (haiku/sonnet/opus);
  state the reason in one line.

Run the **INVEST self-check**: Independent, Negotiable, Valuable, Estimable, Small,
Testable. If the story fails Small/Independent (too big, many criteria) it's really an
Epic — say so and route to `/pm-epic` + `/pm-plan` instead.

## Step 3 — Resolve the tracker + destination (§P2/§P6)

Detect which PM MCP is connected (Linear / Jira / Notion / GitHub Issues). If several,
ask which. Resolve the **team/project/board** from the workspace or ask — never assume
it (§P7). Map the neutral fields onto that tracker per the §P2 table. On **GitHub** the
story is an **Issue** titled `[Story] <title>` with a `story` label, linked to its epic
as a **native sub-issue** (`addSubIssue`); on **Jira** the description is ADF.

## Step 4 — Search before create (§P4)

Search the target project for an existing story matching this work — **strip any
`[Story]` title prefix when matching**. If found, **offer to update it** (append
criteria, set status) rather than creating a duplicate.

## Step 5 — Flag a model mismatch (advisory, never blocking)

If the drafted `recommended_model` differs from the **current session's model**,
say so in one line before proposing the create — e.g. "This story looks
Opus-complexity (cross-cutting redesign); you're on Sonnet. Switch before
implementing, or proceed as drafted?" Skip silently if they match or the hint is
`TBD`. Never block on the answer — proceed either way once said.

## Step 6 — Propose the create, never silently (§P3)

Show the full drafted story — title, story sentence, acceptance criteria, proposed
parent/labels — then:

1. **MCP connected + user opts in** → create the single issue; report its key + URL.
2. **No MCP / user declines** → print **paste-ready markdown** and say nothing was
   created.

Default new issues to the team's default/backlog state; don't set status or assignee
the user didn't ask for (§P7). In non-interactive/CI mode, default to markdown output.

## Report format

```
## Story — <title>

Tracker:  Linear/Jira/… (project <name>)  |  markdown only (no MCP)
Parent:   <epic key, or none>
Story:    As a <persona>, I want <capability>, so that <value>.
Criteria: <n> acceptance criteria
Model:    <haiku|sonnet|opus> — <one-line reason>   |   TBD
Action:   created <KEY> → <url>   |   printed markdown — nothing created
```

## Safety rails

- **Propose, never bulk-create** (§P3). One story, on opt-in, or markdown fallback.
- **Ground scope in intent** — no invented criteria; `TBD`/ask beats fabrication (§P7).
- **Confirm the destination** project; never create in the wrong workspace (§P7).
- **No secrets** in the title/description (§P7). MCP detected, never required (§P6).
