---
name: pm-epic
description: Use this skill when the user asks to "create an epic", "draft an epic in Linear/Jira", "write an epic for this initiative", or wants a well-formed Epic issue. Drafts one Epic — goal, problem, success measure, scope/out-of-scope — plus a SUGGESTED decomposition into candidate stories (as a list; it does not create them). On opt-in it creates the epic in whatever PM tracker is connected via MCP (Linear/Jira/Notion/GitHub Issues), else hands you paste-ready markdown. Never bulk-creates. To actually build the Epic→Stories→Tasks tree, use /pm-plan. Works with any connected tracker; nothing here is project-specific.
version: 0.1.0
---

# PM Epic (PM-authoring)

Drafts one well-formed **Epic** and, on opt-in, creates it in the connected PM tracker.
A leaf skill of the **PM-authoring class** — follow `CONVENTIONS-pm.md` (§P1 ground,
§P2 neutral-model→per-tracker map, §P3 propose-the-create, §P4 tracker idempotence,
§P6 MCP-detect-never-require, §P7 safety).

An Epic is a **large body of work** spanning many stories. This skill writes the epic
and **suggests** how it breaks down — but it creates only the epic. To create the whole
**Epic → Stories → Tasks** tree in one sequential run, use **`/pm-plan`** (which reuses
this skill's drafting).

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  PM-EPIC — PM-AUTHORING                                           ║
╠══════════════════════════════════════════════════════════════════╣
║  Drafts one Epic (goal, problem, success measure, scope) + a      ║
║  SUGGESTED story breakdown, then (on opt-in) creates the epic in  ║
║  your connected tracker — else paste-ready markdown. Creates the  ║
║  epic only; use /pm-plan to build the whole tree.                 ║
╚══════════════════════════════════════════════════════════════════╝
```

## Step 1 — Ground the epic (§P1)

From the user's intent (+ light repo context when it's about this codebase): the
**initiative** — what outcome it drives and why now. Invent no scope (§P7); mark
unknowns `TBD` or ask.

## Step 2 — Draft into the neutral issue model (§P2)

Fill the neutral model with `type: epic`:

- **title** — the initiative, outcome-framed ("Self-serve billing").
- **description** — structured:
  - **Goal** — the outcome, one or two sentences.
  - **Problem / why now** — what this solves.
  - **Success measure** — how you'll know it worked (a metric or observable state).
  - **Scope** and **Out of scope** — bounded explicitly; out-of-scope prevents creep.
- **labels / priority** — if supplied or the tracker needs them.
- (An epic has no acceptance criteria of its own — those live on its stories.)

## Step 3 — Suggest the decomposition (list only — do NOT create)

Propose a breakdown into **candidate stories** (and, where obvious, tasks) as a plain
list — titles + a one-line intent each. This is a **suggestion for the user**, not a
create: creating the children is `/pm-plan`'s job (§P5 sequential build), not this
skill's. Offer: *"Want me to build this whole tree? Run `/pm-plan`."* Keep the breakdown
grounded (§P7) — don't pad it with plausible-but-unasked stories.

## Step 4 — Resolve tracker + destination, search before create (§P2/§P4/§P6)

Detect the connected PM MCP; if several, ask. Resolve team/project/board from the
workspace or ask — never assume (§P7). Search for an existing epic matching this
initiative; **offer to update** rather than duplicate (§P4). Map per the §P2 table
(mind: GitHub Issues has no native Epic type — represent as a label + tracking issue,
and say so; Jira description is ADF).

## Step 5 — Propose the create, never silently (§P3)

Show the full drafted epic + the suggested breakdown, then:

1. **MCP connected + user opts in** → create the **epic** issue; report key + URL. Then
   remind them the stories/tasks aren't created yet — `/pm-plan` does that.
2. **No MCP / user declines** → print **paste-ready markdown** (epic + breakdown list);
   say nothing was created.

Default to the team's default/backlog state; don't set status/assignee unasked (§P7).
Non-interactive/CI → markdown output by default.

## Report format

```
## Epic — <title>

Tracker:  Linear/Jira/… (project <name>)  |  markdown only (no MCP)
Goal:     <one line>          Success measure: <metric/state>
Scope:    <in> / out: <out>
Suggested breakdown: <n> stories (not created)
Action:   created <KEY> → <url>   |   printed markdown — nothing created
Next:     run /pm-plan to build the Epic→Stories→Tasks tree.
```

## Safety rails

- **Create the epic only** — the suggested stories/tasks are a list, not creates.
  `/pm-plan` builds the tree (§P5). **Propose, never bulk-create** (§P3).
- **Ground scope + breakdown in intent** — no invented stories (§P7).
- **Confirm the destination** project; never create in the wrong workspace (§P7).
- **No secrets** in the item (§P7). MCP detected, never required (§P6).
