# nj-agents — shared PM-authoring conventions

The **PM-authoring class** of skills (`pm-epic`, `pm-story`, `pm-task`, `pm-plan`) is
a fourth class alongside review (`CONVENTIONS.md`), authoring
(`CONVENTIONS-authoring.md`), and workflow. Where authoring skills write a **file into
the repo**, PM skills write a **work item into a project-management tracker** (Linear,
Jira, GitHub Issues, Notion). The artifact is a tracker object, not a repo file — so
the authoring placement rules (§A2/§A4) do **not** apply; this doc holds what the PM
skills share instead. When a PM skill says "map per §P2" or "create per §P3," this is
what it means.

The one rule the whole suite shares still holds: **the human decides.** PM skills
draft the item and **propose the create** — they never bulk-create silently.

Related global rule: the global `CLAUDE.md` Standing rule *"Track the work in a PM
tool before non-trivial code"* is the motivation for this class; `/pm-story` and
`/pm-plan` are how that rule creates the tracked item.

---

## §P1 — Ground the item (shared)

Before drafting, gather just enough to write a real work item, not a hollow one:

1. **The user's intent** — the feature/bug/task described, plus any doc/spec/issue
   they point at. This is the primary source.
2. **Light repo context** (per `CONVENTIONS-authoring.md §A1`) when the item is about
   this codebase — name, purpose, the area touched — so scope and acceptance criteria
   are concrete, not generic boilerplate.
3. **Existing tracker context** (per §P4) — is there already an item for this?

**Invent no scope.** Every acceptance criterion, sub-task, or "done when" must trace
to the user's intent or the repo — not to a plausible-sounding guess (`§A6`). If a
detail isn't known, mark it `TBD` or ask; don't fabricate a requirement.

---

## §P2 — The neutral issue model → per-tracker mapping (shared)

PM skills draft into **one neutral issue model**, then map it onto whichever tracker
is connected. This keeps the skills tool-agnostic and the mapping in one place.

**Neutral model:**

```
{
  type:                epic | story | task | bug
  title:               string
  description:         markdown
  acceptance_criteria: string[]      (stories/bugs; a "done when" list)
  parent:              <id of parent item, or null>
  labels:              string[]
  estimate:            number | null
  priority:            none|low|medium|high|urgent
}
```

**Mapping (apply the one for the connected MCP; degrade to markdown otherwise):**

| Neutral field | Linear | Jira | GitHub Issues | Notion |
|---|---|---|---|---|
| `type` | issue + parent (epic = parent issue / project) | `issuetype` (Epic/Story/Task/Bug) | label (`epic`/`story`) — flat | DB `Type` select |
| `title` | `title` | `summary` | title | page title |
| `description` | markdown | **ADF** (convert) | markdown | blocks |
| `acceptance_criteria` | append as a `## Acceptance criteria` checklist in the description | same, in description | task-list in body | checklist blocks |
| `parent` | `parentId` | epic-link / parent | (no native subtasks — reference in body) | `Parent` relation |
| `labels` | `labels` | `labels` | `labels` | multi-select |
| `estimate` | `estimate` | story points field | (none — note in body) | number prop |

Two truths to respect:
- **Not every tracker has every level.** GitHub Issues has no native Epic/subtask
  hierarchy — represent parentage by reference/task-list and say so, don't pretend.
- **Jira descriptions are ADF, not markdown.** Convert (via the MCP's own field), or
  send plain text if conversion isn't available — never send raw markdown as if it
  renders.

The **team/project/board** the item lands in is never assumed — resolve it from the
connected workspace or ask (`§P4`).

---

## §P3 — Propose the create, never bulk-create silently (shared)

The PM analogue of `CONVENTIONS-authoring.md §A3`.

1. **Show the drafted item(s)** in full — title, description, acceptance criteria,
   proposed parent, labels — before anything is created.
2. **Create only on opt-in.** For a single item, confirm and create. For a tree
   (`/pm-plan`), show the **whole proposed tree first** and create only on one explicit
   confirmation — never fire N creates off an ambiguous "ok."
3. **Draft-first where the tracker supports it** (Linear/Jira drafts, GitHub draft PRs
   are unrelated — issues have no draft, so there "propose" means show-then-create).
4. **No MCP connected, or the user declines** → output **paste-ready markdown** for
   each item and stop. Say plainly that nothing was created.

In non-interactive/CI mode, default to draft/markdown output — never create tracker
items without an explicit opt-in.

---

## §P4 — Idempotence on a tracker (shared)

The `§A7` non-clobber rule, adapted from files to tracker objects.

- **Search before create.** Look for an existing item matching the work (title/key
  match in the target team/project) and **offer to update it** — set status, append
  the plan, add sub-items — rather than creating a duplicate.
- **A re-run must not double-create.** `/pm-plan` especially: if part of the tree
  already exists (from a prior partial run), reconcile against it — create only the
  missing items, link to the existing ones.
- **Reference, don't reparent blindly.** When linking to an item you didn't create
  this run, confirm it's the right parent before wiring children under it.

---

## §P5 — Sequential, parent-first creation (shared; the orchestrator's core rule)

For any multi-level create (`/pm-plan`, or a skill that creates an item under a new
parent), ordering is **required, not cosmetic**: a child cannot link to its parent
until the parent exists and has returned an ID.

1. Create the **parent first**; capture its returned ID.
2. Create each child with that ID as `parent`.
3. Recurse depth-first (Epic → its Stories → each Story's Tasks).

**Partial-failure handling:** if a create fails mid-tree, **stop** and report exactly
what was created (with IDs/URLs) and what wasn't — never leave the tree half-built and
silent, and never retry-storm. The user resumes from a known state (`§P4` makes the
resume idempotent).

> This is the same discipline used to file this project's own NAV-80..84 by hand:
> parent issue first, capture the ID, then children under it.

---

## §P6 — MCP detected, never required (shared)

The PM tracker is reached **only** through a connected MCP connector (Linear, Jira,
Notion, a GitHub-issues connector). Per `CONVENTIONS-authoring.md §A5`: **probe at
runtime, use only if present**, and always have the **zero-dependency fallback** —
paste-ready markdown the user files themselves. Never hard-require a connector; never
assume which tracker the project uses. If several are connected, ask which to use.

---

## §P7 — Safety (shared)

- **No secrets in items.** Never put a credential, token, internal hostname, or
  private URL into a title/description (`§A6`).
- **No invented scope or acceptance criteria** — `TBD`/ask beats fabrication.
- **Never create outside the confirmed team/project.** A stray item in the wrong
  workspace is noise that's tedious to clean up — confirm the destination.
- **Don't set status/assignee the user didn't ask for.** Default new items to the
  team's default state (or backlog); let the user drive workflow state.

---

## §P8 — Report the whole tree, not the finished item (shared)

When a tracked item is completed, **end the update with the full parent tree** —
every sibling, not just the one that closed. A bare "NAV-133 done ✅" tells the user
what happened; it does not tell them where they are, so they go and look it up.

Done items first with `✅`, the rest in dependency/priority order, columns aligned,
`← new` on anything added this session. Short titles, not the full tracker title —
this is a glance, not a report:

```
✅ NAV-133  Referential drift
✅ NAV-134  class: frontmatter
   NAV-137  bin/nj-agents-review       URGENT   5pt
   NAV-143  Cost-control harness         High   5pt   ← new
   NAV-141  Harness docs + diagram        Low   5pt
```

Each row: key · short title · priority · estimate. Pair the tree with the commit
SHA and one line on anything surprising found along the way, then let the tree be
the last thing on screen.

Applies to any tracker and to work done **outside** a PM skill — if the session is
executing a tracked plan, the completion report follows this shape.
