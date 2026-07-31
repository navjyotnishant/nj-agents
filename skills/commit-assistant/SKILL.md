---
name: commit-assistant
description: "Use this skill when the user asks to \"write a commit message\", \"help me commit this\", \"draft a conventional commit for these changes\", or wants a clean commit message for the current diff. Reads the working-tree changes, groups them into logically distinct commits when they're unrelated, and drafts a Conventional Commits message for each — then prints the exact `git add` + `git commit` block and OFFERS to run each one, asking per commit and showing exactly what it would stage. Never pushes, never tags, never bypasses a hook — and in CI it prints only. The human decides what gets committed. Works in any git repo; nothing here is project-specific."
version: 0.1.0
class: workflow
author: navjyotnishant
---

# Commit Assistant (workflow)

Drafts **Conventional Commits** messages for the current changes and prints the exact
`git add` / `git commit` block to run. When the working tree holds unrelated changes,
it proposes splitting them into **separate, logically coherent commits** — one message
each — rather than one grab-bag commit.

This is a **workflow-class** skill (see `/pr-describe`). It reads a diff like the
review class but invents nothing (`CONVENTIONS.md §1` scope, `CONVENTIONS-authoring.md
§A6` grounding), and it **proposes before it acts** (§A3): the block is printed first,
every time, and a commit runs only on an explicit per-commit yes.

> **Finding the conventions file.** It lives at the toolkit repo root, two levels
> above this skill — not beside `SKILL.md`. Skills are usually installed as
> symlinks into your runner's skills directory, so a plain relative path resolves against the
> *link* and misses it. Resolve the link first:
>
> ```bash
> ROOT="$(dirname "$(readlink -f "<this skill's base directory>")")/.."
> ```
>
> then read `$ROOT/CONVENTIONS-authoring.md` and `$ROOT/CONVENTIONS.md`. If a file is genuinely absent, say so and continue
> with the procedure below rather than stopping.

> **Every skill follows `CONVENTIONS-orchestration.md` §U** — ground everything in
> the actual repo, never run git on your own initiative, no secrets in output,
> keep `CHANGELOG.md` current when the change is user-facing, degrade rather than
> fail, and say what you did not do.

> **The one hard rule this skill lives on top of:** *the human decides what gets
> committed.* Its core output is the `git commit` block from §A3 — with a good message
> instead of a placeholder — and that block always stands on its own.
>
> It may then **offer** to run each commit, asking **once per commit** and showing the
> exact paths it would stage (Step 6). §U forbids running git on the skill's *own
> initiative* and explicitly allows an explicit go-ahead; a per-commit yes is that
> go-ahead. What never happens: committing something the user has not seen, one
> approval covering several commits, **any `git push` or `git tag`**, `--no-verify`,
> or committing at all in CI mode.

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  COMMIT-ASSISTANT — WORKFLOW                                      ║
╠══════════════════════════════════════════════════════════════════╣
║  Drafts Conventional Commits message(s) from your changes and     ║
║  prints the git add + commit block. Splits unrelated changes into ║
║  separate commits. Grounded in the real diff — nothing invented.  ║
║  Then OFFERS to run each one, asking per commit and showing what  ║
║  it would stage. Never pushes, never tags, never --no-verify.     ║
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

## Step 5 — Print the commit block(s) (§A3)

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

If a pre-commit/pre-push gate exists, note it — but never bypass it (`--no-verify`
is forbidden, whoever runs the command).

## Step 6 — Offer to run each commit, one at a time

The block above is the deliverable and always stands on its own: copy it, ignore the
rest of this step, and nothing is lost. But re-typing a command you have just read
and approved is friction, not safety — so offer to run it.

**Ask per commit, never once for the batch.** Splitting unrelated changes is this
skill's whole point; a single yes covering three commits throws that away and
approves messages the user has not seen land yet.

For each group in order, show **exactly what would be staged** — the human is
approving a set of paths, not a sentence — then ask:

```
Commit 1 of 2 — feat(list): paginate results with a cursor API
  will stage:  src/list.js  src/api.js  src/list.test.js

  [y] run it   [n] skip this one   [e] edit the message   [a] stop here
```

Then:

- **y** — run `git add` for exactly those paths, then `git commit`. Print the real
  `git` output (the `[main a1b2c3d]` line), not a paraphrase. Move to the next.
- **n** — skip it, leave those paths unstaged, continue. A skipped commit does not
  block the ones after it; they were grouped as independent.
- **e** — take the revised message and re-show the prompt. Never commit a message
  the user is still editing.
- **a** — stop entirely. Report what was committed and what was not.

**Re-read the tree between commits.** Committing changes what is staged and what
`git status` reports, so a plan computed once can be stale by commit 3 — a file may
have already gone in, or been touched. If the staged set no longer matches the plan,
say so and re-confirm rather than staging something the user did not approve.

**If any `git` command fails** — a pre-commit hook rejects it, a path has vanished —
stop immediately. Do not continue to the next commit, do not retry, and never reach
for `--no-verify`. Report which commits landed and which did not, so the user resumes
from a known state.

**Non-interactive/CI mode** (`NJ_AGENTS_CI=1`, `CONVENTIONS.md §5`): print the blocks
and stop. There is nobody to ask, and an unattended commit is exactly the thing the
"human decides" rule exists to prevent.

This does not weaken `§U`'s **the human decides what gets committed**. That rule
forbids running git *on the skill's own initiative*; it explicitly allows an explicit
go-ahead from the user. Asking and being told yes is that go-ahead — collected in the
session instead of in a shell. What stays forbidden: committing anything the user has
not seen, batching the approval, pushing (never offered), and `--no-verify`.

## Report format

```
## Commit plan — <N> commit(s)

Staged already: <paths, or "nothing — grouped the whole tree">
Style:          Conventional Commits (repo convention) | <repo's own style>

1. <type(scope): subject>  → <paths>
2. <type(scope): subject>  → <paths>

Committed:      <keys/SHAs of the ones you said yes to, or "none — blocks printed only">
Not committed:  <skipped, aborted, or left for you to run by hand>
Pushed:         nothing — this skill never pushes
Skipped/uncertain: <e.g. untracked file left out, ambiguous grouping>
```

## Safety rails

- **Never commit anything the user has not seen and approved.** The block is printed
  first, always; `git add`/`commit` run only on an explicit per-commit yes (Step 6).
  One approval never covers more than one commit.
- **Never `git push` or `git tag`.** Not offered, not on request — this skill stops at
  the commit. Pushing is a separate conscious act.
- **Never `--no-verify`, never bypass a hook.** If a gate rejects a commit, stop and
  report; do not retry around it.
- **Print blocks only in CI/non-interactive mode** (`NJ_AGENTS_CI=1`) — there is
  nobody to ask, so there is no approval to act on.
- **Respect existing staging** as the user's stated intent.
- **Ground every message in the diff** (§A6) — no invented rationale, no `fix bug`.
- **Match the repo's commit style**, including a `no Co-Authored-By`-type rule.
- **Don't over-split** — one coherent change is one commit.
- Keep any working notes out of the repo tree (scratchpad/temp only).
