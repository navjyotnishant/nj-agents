---
name: pm-task
description: Use this skill when the user asks to "create a task", "add a task/sub-task in Linear/Jira", "break this into a task", or wants a single well-formed Task issue. Drafts one scoped, actionable Task (optionally under a parent Story/Epic), then — on opt-in — creates it in whatever PM tracker is connected via MCP (Linear/Jira/Notion/GitHub Issues), else hands you paste-ready markdown. Never bulk-creates; grounds the task in your intent, never invents. Works with any connected tracker; nothing here is project-specific.
version: 0.1.0
---

# PM Task (PM-authoring)

Drafts one scoped, actionable **Task** and, on opt-in, creates it in the connected PM
tracker. A leaf skill of the **PM-authoring class** — follow `CONVENTIONS-pm.md`
(§P1 ground, §P2 neutral-model→per-tracker map, §P3 propose-the-create, §P4 tracker
idempotence, §P6 MCP-detect-never-require, §P7 safety).

A Task is the **unit of work** — smaller and more concrete than a Story. Where a Story
says *what a user gets*, a Task says *what someone does*. Use `/pm-story` if the thing
is really a user-facing capability with acceptance criteria.

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  PM-TASK — PM-AUTHORING                                           ║
╠══════════════════════════════════════════════════════════════════╣
║  Drafts one scoped, actionable task, then (on opt-in) creates it  ║
║  in your connected tracker — else hands you paste-ready markdown. ║
║  Never bulk-creates; grounded in your intent, never invented.     ║
╚══════════════════════════════════════════════════════════════════╝
```

## Step 1 — Ground the task (§P1)

From the user's intent (+ light repo context when it's about this codebase): **what
concrete action** is to be done, in **which area**, and **when it's done**. Invent no
scope (§P7); `TBD`/ask beats a fabricated requirement.

## Step 2 — Draft into the neutral issue model (§P2)

Fill the neutral model with `type: task`:

- **title** — an imperative action ("Add DB index on `search.created_at`").
- **description** — what to do and any how/constraints; a short **done-when** line if it
  sharpens scope (tasks don't need full acceptance criteria the way stories do).
- **parent** — the parent Story/Epic ID if the user names one (optional; a task is often
  a child of a Story).
- **labels / estimate / priority** — only if supplied or the tracker needs them.

Keep it **small and single-purpose**. If it sprawls into several actions, propose
splitting into multiple tasks rather than one vague one.

## Step 3 — Resolve the tracker + destination (§P2/§P6)

Detect the connected PM MCP (Linear / Jira / Notion / GitHub Issues); if several, ask.
Resolve team/project/board from the workspace or ask — never assume (§P7). Map per the
§P2 table (Jira description is ADF; GitHub Issues has no native subtask — reference the
parent in the body).

## Step 4 — Search before create (§P4)

Search the target project for an existing task matching this work; **offer to update**
rather than duplicate.

## Step 5 — Propose the create, never silently (§P3)

Show the drafted task — title, description, proposed parent/labels — then:

1. **MCP connected + user opts in** → create the single issue; report key + URL.
2. **No MCP / user declines** → print **paste-ready markdown**; say nothing was created.

Default to the team's default/backlog state; don't set status/assignee unasked (§P7).
Non-interactive/CI → markdown output by default.

## Report format

```
## Task — <title>

Tracker:  Linear/Jira/… (project <name>)  |  markdown only (no MCP)
Parent:   <story/epic key, or none>
Action:   created <KEY> → <url>   |   printed markdown — nothing created
```

## Safety rails

- **Propose, never bulk-create** (§P3). One task, on opt-in, or markdown fallback.
- **Ground in intent** — no invented scope; `TBD`/ask over fabrication (§P7).
- **Confirm the destination** project (§P7). No secrets in the item (§P7).
- **MCP detected, never required** (§P6); markdown path always works.
