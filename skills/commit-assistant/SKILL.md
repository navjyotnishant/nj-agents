---
name: commit-assistant
description: Use this skill when the user asks to "write a commit message", "help me commit this", "draft a conventional commit for these changes", or wants a clean commit message for the current diff. Reads the working-tree changes, groups them into logically distinct commits when they're unrelated, and drafts a Conventional Commits message for each — then prints the exact `git add` + `git commit` block for the user to run. It NEVER runs git itself: the human decides what gets committed. Works in any git repo; nothing here is project-specific.
version: 0.1.0
---

# Commit Assistant (workflow)

Drafts **Conventional Commits** messages for the current changes and prints the exact
`git add` / `git commit` block to run. When the working tree holds unrelated changes,
it proposes splitting them into **separate, logically coherent commits** — one message
each — rather than one grab-bag commit.

This is a **workflow-class** skill (see `/pr-describe`). It reads a diff like the
review class but invents nothing (`CONVENTIONS.md §1` scope, `CONVENTIONS-authoring.md
§A6` grounding), and it **proposes, never acts** (§A3).

> **The one hard rule this skill lives on top of:** *the human decides what gets
> committed.* This skill's entire output is the `git commit` block from §A3 — with a
> good message instead of a placeholder. **It never runs `git add`, `git commit`,
> `git push`, or `git tag`**, in interactive or CI mode. No exceptions, no `--no-verify`.

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  COMMIT-ASSISTANT — WORKFLOW                                      ║
╠══════════════════════════════════════════════════════════════════╣
║  Drafts Conventional Commits message(s) from your changes and     ║
║  prints the git add + commit block. Splits unrelated changes into ║
║  separate commits. Grounded in the real diff — nothing invented.  ║
║  It NEVER runs git — you review and run the commands yourself.    ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **Uncommitted changes.** If the tree is clean, report "nothing to commit — working
  tree clean" and stop.
- **No API key / no network.** The drafting is done by the current session.

## Step 1 — Read the changes and honor explicit staging

```bash
git status --short         # what's staged (index) vs unstaged vs untracked
git diff --cached          # staged delta
git diff                   # unstaged delta
```

**Respect the user's staging as intent.** If something is **already staged**, treat
that as "this is the commit I mean" — describe the staged set as one commit and do not
drag in unstaged changes (offer them as a follow-up, don't merge them). Only when
**nothing is staged** do you consider the whole working tree and propose grouping.

If the user gave an explicit instruction ("just the staged ones", "everything as one",
"a commit for the auth files"), honor it over the grouping heuristic below.

## Step 2 — Group into logical commits (when nothing is staged)

Cluster the changes into **coherent units** — a unit is a set of hunks that belong in
one commit because they serve one purpose. Signals: shared directory/module, a feature
and its tests, a fix and its regression test, a rename across files. Keep **unrelated**
changes apart — a feature and a drive-by typo fix are two commits.

- **One coherent change** → one commit (the common case; don't over-split).
- **Multiple unrelated changes** → propose N groups, each with its own `git add
  <paths>` + message. Present the grouping and let the user collapse or re-split it.
- **Untracked files:** include only when they're clearly part of a group; call them out
  explicitly (they're new files, easy to add by accident).

Never propose adding paths the user didn't change. Keep any working notes in the
scratchpad, never in the repo tree.

## Step 3 — Ingest light repo context (§A1) for message style

Match the repo's existing commit conventions rather than imposing a fixed style:

```bash
git log --no-merges -20 --format='%s'      # recent subjects → detect the house style
```

- Does the repo use **Conventional Commits** (`feat:`/`fix:`/`docs:`/…)? If yes, match
  it, including any **scope** convention (`feat(api):`) visible in the log. If the repo
  clearly does *not*, follow its actual style instead of forcing conventional prefixes —
  but say that's what you did.
- Note any repo rule from `CLAUDE.md`/`CONVENTIONS*.md` (e.g. "no `Co-Authored-By`",
  "no emoji") and follow it.

## Step 4 — Draft the message(s)

Per group, write a Conventional Commit:

- **Subject:** `type(scope): imperative summary`, ~50 chars, no trailing period.
  Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`,
  `style`. Pick from what the diff actually does — not from the filename alone.
- **Body** (only when it adds information): wrap ~72 cols; explain the *why* and any
  non-obvious *what*. Skip the body for a genuinely trivial change.
- **Breaking change:** if the diff removes/renames a public API or changes a contract,
  use `type!:` and a `BREAKING CHANGE:` footer. Only when the diff supports it.
- **Footers:** issue refs (`Refs #123`, `Closes #123`) when the branch/context supports
  them — never assert a `Closes` you can't ground (§A6).

**Grounding (§A6):** the message describes what the diff *does*. No "improve
performance," "clean up," or "fix bug" unless a concrete change backs it. Don't invent a
motivation the changes don't show — if the *why* isn't derivable, keep the body factual
or omit it.

## Step 5 — Print the commit block(s), never run them (§A3)

For each group, print a copy-paste block, `git push` deliberately **omitted** (this
skill stops at the commit; pushing is a separate conscious act):

````
Commit 1 of 2 — feat: cursor-based pagination
```bash
git add src/list.js src/api.js src/list.test.js
git commit -m "feat(list): paginate results with a cursor API" \
           -m "Replaces offset paging, which double-counted rows on concurrent
inserts. Cursor is opaque and stable across page size changes."
```

Commit 2 of 2 — docs: typo
```bash
git add README.md
git commit -m "docs: fix broken install link in README"
```
````

Then stop. **Never execute any of these.** If a pre-push/pre-commit gate exists, note
it but never bypass it (`--no-verify` is forbidden).

## Report format

```
## Commit plan — <N> commit(s)

Staged already: <paths, or "nothing — grouped the whole tree">
Style:          Conventional Commits (repo convention) | <repo's own style>

1. <type(scope): subject>  → <paths>
2. <type(scope): subject>  → <paths>

Blocks printed above for you to run. Nothing was committed or pushed.
Skipped/uncertain: <e.g. untracked file left out, ambiguous grouping>
```

## Safety rails

- **Never run `git add` / `commit` / `push` / `tag`** — print blocks only (§A3).
  Holds in CI/non-interactive mode too. No `--no-verify`, never bypass a gate.
- **Respect existing staging** as the user's stated intent.
- **Ground every message in the diff** (§A6) — no invented rationale, no `fix bug`.
- **Match the repo's commit style**, including a `no Co-Authored-By`-type rule.
- **Don't over-split** — one coherent change is one commit.
- Keep any working notes out of the repo tree (scratchpad/temp only).
