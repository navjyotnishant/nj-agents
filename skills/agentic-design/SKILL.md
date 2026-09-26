---
name: agentic-design
description: Use this skill when the user asks to "design an agentic system", "add the agent loop, tools and evals to the spec", "how should this agent be evaluated", or is specifying or planning software whose core is an LLM agent — tool calls, a loop, state carried between steps. Writes an Agentic design section (loop bounds, tool contracts, state/graph, eval plan, harness) into the spec or plan it is given, or into docs/design/agentic-design.md, and proposes the commit. Writes nothing for a system that is not agent-shaped. Works in any git repo; nothing here is project-specific.
version: 0.1.0
class: authoring
author: navjyotnishant
---

# Agentic Design (authoring)

Designs the parts of an agent-shaped system that a general spec pass leaves out:
**what bounds the loop, what a tool is versus a step, what state the graph carries,
how anyone will know it got better, and what the evals replay against.** It writes one
**Agentic design** section and proposes the commit.

It will **never** pick an orchestration framework, a model, or a hosting target the
intent did not name — those go to Open Questions. It will **never** write the section
for a system that is not agent-shaped: an ordinary CRUD service does not need a loop
bound, and a section describing one would be invented.

This is an **authoring-class** skill — follow `CONVENTIONS-authoring.md` **§A1**
(read the repo and the intent first), **§A3** (show the diff, print the exact
`git add`/`git commit` block, never run git), **§A4** (the section lands at a named
place, below), **§A6** (every element traces to the intent or spec; a gap is marked,
not filled) and **§A7** (re-running updates the section in place, never appends a
second one).

> **Finding the conventions file.** It lives at the toolkit repo root, two levels
> above this skill — not beside `SKILL.md`. Skills are usually installed as
> symlinks into your runner's skills directory, so a plain relative path resolves
> against the *link* and misses it. Resolve the link first:
>
> ```bash
> ROOT="$(dirname "$(readlink -f "<this skill's base directory>")")/.."
> ```
>
> then read `$ROOT/CONVENTIONS-authoring.md`. If it's genuinely absent, say so and
> continue with the procedure below rather than stopping.

> **Every skill follows `CONVENTIONS-orchestration.md` §U** — ground everything in
> the actual repo, never run git on your own initiative, no secrets in output,
> keep `CHANGELOG.md` current when the change is user-facing, degrade rather than
> fail, and say what you did not do.

This is a single-pass design, done entirely by the current session — no subagent, no
external tool, no network.

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  AGENTIC-DESIGN — AUTHORING                                       ║
╠══════════════════════════════════════════════════════════════════╣
║  Writes the Agentic design section: loop bounds, tool contracts,  ║
║  state/graph, eval plan, harness. Unauthorized choices become     ║
║  Open Questions. Proposes the commit; never runs git.             ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **An intent to design from** — `docs/intent/*.md`, a spec, a plan, or a description
  given in conversation. With none, stop and ask; a design with nothing to trace to
  is invented (§A6).

## Step 1 — Ingest, and decide whether this is agent-shaped

Read the intent, and the spec or plan if one exists (§A1). The system is
**agent-shaped** when its core behaviour is a model deciding what to do next —
calling tools, looping until a goal is met, carrying state between steps. Signals: it
names an LLM, an agent, tool or function calling, a loop or retry until done,
multi-step reasoning, or evals.

**Not agent-shaped → write nothing.** Say so in one line, name the signal you looked
for, and stop. A single prompt-in/text-out call is not an agent; it gets no loop bound.

## Step 2 — Write the section

Write it to the first of these that applies (§A4):

1. **A file the caller names** — when a pipeline stage invokes this skill for its own
   spec or plan, the section goes into that file.
2. **`docs/design/agentic-design.md`** — standalone use.

The section is headed `## Agentic design` and has exactly these parts. If one is
already there, replace it in place (§A7).

### Loop

What ends the loop, in order of precedence: goal reached, **max steps**, **max
retries per tool**, **wall-clock** and **cost ceilings**. Each bound is a **named
config value**, never a number buried in a prompt — an agent asked to judge when to
stop is a loop that stops when it feels like it. State what happens at each bound
(return partial result, escalate, fail loudly), because "stops" is not a behaviour.

### Tools and steps

The boundary first: a **tool** is something the model chooses to call; a **step** is
something the code always does. Anything that must happen every time — validation,
logging, a permission check — is a step, not a tool the model may skip. Then one row
per tool:

| Tool | Input | Output | Fails how | Side effects | Idempotent |
|---|---|---|---|---|---|

A tool with a side effect and no idempotence is a retry hazard — say how retries are
made safe or forbid them.

### State and graph

What state is carried between steps, where it is persisted, and where control
branches. Draw it only if the branches are real; a straight line needs no graph. Name
what is **not** carried — context that grows without bound is a cost and a failure mode.

### Eval plan

How anyone will know the agent got better, not just that it runs. Cases must
**discriminate**: each one names the plausible wrong answer it catches. A suite of
happy paths passes on a broken agent. Include at least one case per tool failure mode
and one per loop bound.

Write the plan as a fenced `json` block directly under this heading, in exactly this
shape — a pipeline stage parses it to scaffold `evals/cases/`, so the field names are
a contract:

```json
{
  "gate": { "pass_rate": 0.95, "min_cases": 20 },
  "harness": {
    "command": "how to run the agent on one prompt: prompt on stdin, answer on stdout",
    "replays_against": "recorded fixtures | fakes | a sandbox — and why"
  },
  "cases": [
    {
      "name": "kebab-case-name",
      "prompt": "the input",
      "must_contain": ["text the answer must include"],
      "must_not_contain": ["the plausible wrong answer"],
      "shell_check": "optional command that must exit 0",
      "discriminates": "what a wrong agent does here that this case catches"
    }
  ]
}
```

`min_cases` is the size the suite must reach before any gate trusts it; the starter
cases here can be fewer — say how many, and that the gap is real work, not padding.
If `harness.command` is not knowable yet, write `"TBD"` and add an Open Question; do
not invent an entrypoint.

### Harness

What the evals run against and why: recorded model responses for determinism, fakes
for tools with side effects, or a sandbox. A harness that calls live paid APIs on
every CI run is a cost decision — name it.

### Open questions

Every choice the intent did not authorize: orchestration framework, model, hosting,
where state is persisted. Worded as the actual choice on the table. Confidence is not
authority — an obvious default is still a default nobody agreed to.

## Step 3 — Propose the commit (§A3), never run git

Show `git status` and the diff of the section, then print the block for the human:

```bash
git add <the file from Step 2>
git commit -m "docs(design): agentic design — loop, tools, evals"
```

Never run it. If a pipeline stage invoked this skill for its own spec or plan, say so
and leave the commit to that stage.

## Step 4 — Report

One screen: the file written, the loop bounds as named config, the tool count, the
starter case count against `min_cases`, and every Open Question. If the system was not
agent-shaped, the report is that one line and nothing else.

## Safety rails

- **Never writes a section for a system that is not agent-shaped** — an invented loop
  bound is worse than none.
- **Never picks a framework, model or host the intent did not name** — those are Open
  Questions (§A6).
- **Never writes placeholder eval cases** that pass by construction; every case names
  what it discriminates.
- **Proposes the commit, never runs git** (§A3).
- **Degrade, don't fail** — no external tool is needed; with no intent file, work from
  the conversation and say so (§A5).
- **Ground everything in the actual repo** — no invented APIs, paths, or results.
