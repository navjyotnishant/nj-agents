# Class contracts

Every skill declares a `class:` in its frontmatter. That declaration is not
decoration — it selects which rules `check.sh` holds the skill to.

## What each class must prove

| Class | Must contain | Why |
|---|---|---|
| `review` | `NJ_AGENTS_CI` or a `CONVENTIONS.md §5` reference | A review skill with no CI mode cannot gate a pipeline |
| `review` + `subclass: gate` | A `BLOCK` verdict | A gate that cannot block is not a gate |
| `authoring` | `§A3` and `§A4` | Must propose the commit, and say where its artifact lands |
| `pm` | `§P2` and a paste-ready-markdown fallback | Must work when no tracker is connected |
| `workflow` | A statement that it never runs git | The class's whole promise |

## gate vs scan

Review class splits in two, and the distinction is load-bearing:

- **`gate`** reviews a **diff** and answers *"is this safe to push?"* — PASS / WARN /
  BLOCK, and a hook can act on the verdict.
- **`scan`** sweeps the **whole repo** for accumulated debt and returns candidates.
  There is no sensible BLOCK for *"you have 12 unused exports."*

Only gates are held to the verdict tokens.

That split is read from the `subclass:` key — **never from a list of skill names**. A
hardcoded allow-list would silently exempt skill #24, which is precisely the
forget-to-update failure the harness exists to catch.

## Spawning skills carry two extra obligations

Any skill that spawns subagents — whatever its class — also follows
`CONVENTIONS-orchestration.md`:

**§C — cost.** State the cost shape before the first dispatch, cap fix rounds at 2,
halt on any signal to stop. The user should never discover the cost mid-run.

**§R — progress.** Announce the roster before dispatch, then mark each agent as it
lands. This binds the **skill**, not the agent: a subagent returns once, at the end,
with no channel to stream status — so the spawning skill is the only place that can
make a multi-agent run legible.

Both are enforced by spawn detection, not a skill list.

## Behavioural contracts

Four contracts are asserted against real runs rather than text:

| Contract | Asserted as |
|---|---|
| Review class leaves no files | File listing and `git status` byte-identical before and after |
| No skill ever commits | `HEAD` unchanged, nothing staged |
| `review-secrets` blocks with no scanner | **Zero agents spawned** — structural, not a grep for "BLOCK" |
| Authoring writes exactly one artifact | One new path, at the declared `§A4` location, existing content preserved |

The third is worth dwelling on. Asserting *"the output contains BLOCK"* would pass if
a summary merely mentioned the word. Asserting *"no subagent was spawned"* proves the
diff was never shared with anything — which is the actual promise.
