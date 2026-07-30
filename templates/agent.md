---
name: AGENT_NAME
description: "Use this agent to <what it does, in one sentence — the trigger>. It <how it works: what it reads, what it returns, what it refuses to do>. Works in any repo.\n\n<example>\nContext: <the situation where a skill would spawn this>.\nuser: \"<what the user said>\"\n<commentary>\n<which skill spawns this agent, at which step, and what happens with its output>\n</commentary>\nassistant: \"<the one line announcing the spawn>\"\n</example>"
model: sonnet
color: blue
author: AUTHOR_NAME
---

<!--
  Scaffolded by `./check.sh --new-agent`. Fill every ALL-CAPS placeholder, then run
  `./check.sh`. Delete these comments before committing.

  name         MUST equal the filename without .md
  description  ONE double-quoted string with literal \n escapes, embedding an
               <example> block — this is what makes the agent discoverable
  color        green | red | teal | orange | magenta | yellow | blue | cyan
  model        currently sonnet across the toolkit; see NAV-146 (model-agnostic)

  An agent is spawned BY a skill. Before writing one, be sure the work genuinely
  needs a separate context — if the skill can do it inline, do not add an agent.
  Every agent must be referenced from at least one SKILL.md or check.sh flags it
  as an orphan.
-->

# AGENT TITLE

<One paragraph: the single job this agent does, and the boundary of it.>

## What you receive

<Exactly what the spawning skill passes in — the diff snapshot, the repo model, the
file paths. Be specific; the agent cannot ask for more.>

## What you do

1. <Step.>
2. <Step.>

<Ground every claim in what you were given. Never invent a file, API, version, or
result. If you cannot verify something, say so — an unverifiable claim is a finding,
not a detail to smooth over.>

## What you return

<The exact shape the skill expects. A verdict, a structured list, a document. If the
skill parses it, say the format precisely.>

## What you must NOT do

- **Never write to the repo** unless this agent's whole purpose is producing an
  artifact, and the spawning skill said where it goes.
- **Never run git.** The human decides what gets committed.
- <The specific refusals for this agent's job.>
