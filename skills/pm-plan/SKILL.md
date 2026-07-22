---
name: pm-plan
description: Use this skill when the user asks to "plan out this feature", "break this epic into stories and tasks", "set up the whole initiative in Linear/Jira", or wants a feature-sized ask turned into a created Epic→Stories→Tasks tree. It decomposes the initiative (via the pm-decomposer agent), previews the WHOLE tree for one approval, then creates it in the connected PM tracker SEQUENTIALLY, parent-first — Epic, then Stories under it, then Tasks under each — wiring parent links as it goes. Stops and reports on any partial failure; never bulk-creates without preview + opt-in; else hands you the whole tree as markdown. Works with any connected tracker; nothing here is project-specific.
version: 0.1.0
---

# PM Plan (PM-authoring — orchestrator)

Turns a feature-sized initiative into a **created Epic → Stories → Tasks tree**. The
umbrella of the **PM-authoring class**: it decomposes (via `pm-decomposer`), previews
the whole tree, and — on one explicit opt-in — creates it **sequentially, parent-first**
in the connected tracker. Follow `CONVENTIONS-pm.md`, especially **§P5 (sequential
parent-first creation, stop-on-partial-failure)**, plus §P1 ground, §P2 map, §P3
propose, §P4 idempotence, §P6 MCP-detect, §P7 safety.

It reuses the leaf skills' concerns (`/pm-epic`, `/pm-story`, `/pm-task`) — same neutral
model, same tracker mapping — but is the only PM skill that creates **many** items in
one run, so its guardrails are the strictest in the class.

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  PM-PLAN — PM-AUTHORING (orchestrator)                            ║
╠══════════════════════════════════════════════════════════════════╣
║  Breaks an initiative into an Epic→Stories→Tasks tree, previews   ║
║  the WHOLE tree for one approval, then creates it parent-first in ║
║  your tracker. Stops on any partial failure. No preview-less      ║
║  bulk-create; no MCP → the whole tree as markdown.                ║
╚══════════════════════════════════════════════════════════════════╝
```

## Step 1 — Ground the initiative (§P1)

Gather the initiative from the user's intent + any doc/spec they point at + light repo
context. Resolve the **target tracker** (connected PM MCP; if several, ask) and the
**destination team/project/board** — never assume it (§P7). Note the tracker's shape so
the plan fits it (GitHub Issues has no native Epic/subtask — flatten + reference).

## Step 2 — Decompose (spawn `pm-decomposer`)

Spawn the **`pm-decomposer`** agent with the initiative + tracker capabilities. It
returns a structured **Epic → Stories → Tasks** tree in the §P2 neutral model, plus
`open_questions` and any items marked `assumption`. It **creates nothing**.

If it returns **open questions** that block responsible planning, surface them and
resolve with the user **before** creating anything — don't create a tree built on
guesses.

## Step 3 — Search before create (§P4)

Before proposing creates, search the destination project for anything matching this
initiative — an existing epic, or stories from a prior partial run. **Reconcile:** mark
which planned items already exist (link to them) versus which are new to create. A
re-run must **not** double-create (§P4).

## Step 4 — Preview the WHOLE tree, get ONE opt-in (§P3)

Show the complete proposed tree before creating anything:

```
Epic:  <title>
  ├─ Story: <title>            [new]        (3 acceptance criteria)
  │   ├─ Task: <title>         [new]
  │   └─ Task: <title>         [new]
  ├─ Story: <title>            [exists → link]  ENG-42
  └─ Story: <title>  [assumption]  [new]
Open questions resolved: <…>
Will create: <N> items in <project> on <tracker>.  Nothing yet created.
```

Mark `[assumption]` items clearly so the user can cut them. Then create **only on one
explicit confirmation** — never fire N creates off an ambiguous "ok" (§P3). If **no MCP
/ the user declines**, print the whole tree as **paste-ready markdown** and stop.

## Step 5 — Create sequentially, parent-first (§P5 — the core rule)

Ordering is **required, not cosmetic**: a child can't link to a parent that has no ID
yet. Create depth-first, capturing each returned ID:

1. Create the **Epic**; capture its ID/URL. (Or use the existing one from Step 3.)
2. For each Story: create it with `parent = epic_id`; capture its ID.
3. For each Task under that Story: create it with `parent = story_id`.

Map each item onto the tracker per §P2 as you go (ADF for Jira; label+reference for
GitHub Issues). Default each item to the team's default/backlog state; set no
status/assignee the user didn't ask for (§P7).

**Stop-on-partial-failure (§P5):** if any create fails, **halt immediately** — do not
continue the tree, do not retry-storm. Report exactly what was created (with keys/URLs)
and what wasn't, so the user resumes from a known state. Because Step 3 reconciles, a
re-run of `/pm-plan` picks up where it stopped without duplicating.

## Step 6 — Report

```
## Plan created — <epic title>

Tracker:  Linear/Jira/… (project <name>)   |   markdown only (no MCP)
Created:  Epic <KEY> + <s> stories + <t> tasks       (all links wired)
Linked:   <items that already existed>
Skipped:  <assumption items the user cut>
Status:   complete   |   HALTED after <KEY> — <what failed>; re-run to resume
Epic URL: <url>
```

## Safety rails

- **Whole-tree preview + ONE explicit opt-in before any create** (§P3). Never
  preview-less bulk-create. Non-interactive/CI → markdown only, create nothing.
- **Sequential parent-first; stop on partial failure** (§P5) — never leave a half-built
  tree silent, never retry-storm.
- **Search-before-create + reconcile** so a re-run doesn't duplicate (§P4).
- **Confirm the destination** project; never create in the wrong workspace (§P7).
- **Ground the tree in intent** — `assumption`-flag anything inferred; resolve open
  questions before creating; no invented scope (§P7). No secrets in items (§P7).
- **MCP detected, never required** (§P6); the markdown fallback always works.
