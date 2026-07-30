# nj-agents — shared orchestration conventions

Rules for **any skill that spawns subagents**, in any class. Where the per-class
conventions docs (`CONVENTIONS.md`, `CONVENTIONS-authoring.md`, `CONVENTIONS-pm.md`)
say *what* a class produces, this one says how a skill behaves while producing it:
what it costs (`§C`) and what the developer sees while it runs (`§R`).

It is deliberately class-agnostic. Cost control originally lived in
`CONVENTIONS.md §8`, the review-class doc — which meant authoring and PM skills, the
ones running the longest pipelines in the toolkit, had no cost rules to cite. A
skill spawning six agents costs the same whatever class it belongs to.

**Who this binds:** every skill whose procedure spawns an agent. `check.sh` detects
that from the skill's own text rather than a list of names, so a skill added
tomorrow is covered the moment it says "spawn".

---

## §C — Cost control (every skill that spawns agents)

Each subagent costs real money against the user's plan, and several skills here run
render→QA→fix or find→verify loops that can go many rounds. Treat spend as a budget
to manage, not an implementation detail.

**State the cost shape before spawning anything.** One line, before the first
dispatch, naming the fleet size and the loop shape — then, in interactive mode, get
a yes:

```
Scope: 12 files, 340 reviewable lines (2 lockfiles, 1 image excluded)
Plan:  5 dimension agents in parallel (secrets-semantic, correctness,
       tests/build, dependencies, style)
Proceed? [Y/n/pick dimensions]
```

For a loop, say the bound up front: *"render → QA → fix, usually 2–4 agent calls,
hard cap 2 fix rounds."* The user can accept, decline, or name a subset. Skip the
prompt only in non-interactive/CI mode (`CONVENTIONS.md §5`), where there is nobody
to ask.

**Scale the fleet to the work.** Do not spawn an agent that has nothing to do — a
skipped agent is free, and `SKIP — no dependency manifests changed` is more
informative than a report that spent tokens confirming it.

| Signal | Action |
|---|---|
| No dependency-manifest changes in the diff | `SKIP` the dependencies dimension |
| No test/lint/build command detected | `SKIP` tests/build (report the miss) |
| Docs-only diff (`*.md`, no source) | Offer style-only; skip correctness |
| Trivial diff (< ~20 lines, 1–2 files) | Offer a single inline review, no fleet |
| Very large diff (`CONVENTIONS.md §2` cap) | Say the review is partial, and that top-N scoping is what bounds the cost |

**Re-runs are the expensive case.** A user fixing findings will re-run. Default to
only the parts that still have open findings, and say so:

```
Re-run: correctness + style only (the 2 dimensions with open findings).
Add --all to re-review everything.
```

**Hard stops.**
- **Cap fix rounds at 2, then ASK.** After two cycles on the same artifact, stop and
  report what's fixed and what still fails — then offer the choice explicitly:
  *"Ship as-is, or run 2 more rounds?"* Never start a third round unprompted, and
  never quietly abandon the work either. The cap makes spend a decision rather than a
  side-effect; the question is what keeps it from becoming a dead end.
- **A blocking verdict is a checkpoint, not a to-do.** When a QA/review agent returns
  BLOCK, surface it — do not silently fix and re-run. Say what it found and what
  fixing it would cost.
- **Halt on any signal to stop** — "this is expensive", "that's taking a while", a
  suggested change of approach, or an interrupt. Do not acknowledge and continue.
- **Never chain into another agent-spawning skill** because this one suggested it.
  Report the finding; let the user invoke the fix.

**Cheap path first.** If a scanner, a linter, a one-line flag, or a single targeted
read answers the question, do that and offer the fleet as the upgrade. A skill is not
automatically the right tool because it matches the topic.

---

## §R — Progress reporting (every skill that spawns agents)

A subagent returns **once, at the end** — it has no channel to stream status while it
works. So the *spawning skill* is the only place that can make a multi-agent run
legible, and it must.

Without this, a six-agent pipeline is a silent gap ending in a wall of output, and
the developer cannot tell whether it is working, stuck, or looping.

**Announce the roster before dispatch.** Every agent, and what it will do:

```
Dispatching 5 agents in parallel:
  ⋯ secrets-reviewer      semantic security pass
  ⋯ correctness-reviewer  logic + regressions
  ⋯ tests-build-runner    detect and run the repo's commands
  ⋯ dependency-reviewer   manifest + license changes
  ⋯ style-reviewer        conventions + commit hygiene
```

**Mark each one as it lands**, with a one-line result — not a summary, the verdict:

```
  ✓ style-reviewer        PASS — no findings
  ✓ secrets-reviewer      WARN — 1 finding
  ✗ tests-build-runner    BLOCK — 3 tests failing
```

**Distinguish the two shapes**, because they read differently:

- **Parallel fan-out** — all dispatched at once; print the whole roster, then mark
  results as they arrive in whatever order they finish.
- **Sequential pipeline** — each stage feeds the next; print the chain
  (`blog-writer → blog-fact-checker → blog-reviewer → …`) and announce each stage as
  it starts, so a stall is attributable to a named stage.

**Loops report the round against the cap** — `round 2/2` — so a loop that looks
unbounded visibly shows its bound (`§C`).

The glyphs are a detail; the roster-then-drain shape is the requirement. What matters
is that at any moment the developer can see what was dispatched, what has come back,
and what is still outstanding.
