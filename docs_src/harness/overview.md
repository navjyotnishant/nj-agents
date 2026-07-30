# The verification harness

Every contract in this toolkit used to be prose telling a model what to do — *"review
class leaves no files"*, *"cap fix rounds at 2"*, *"loop render → QA → fix until
PASS"*. Nothing checked that it happened.

That failure mode is silent and remote. A skill stops honouring a rule, nothing
complains, and it surfaces weeks later in a different repo as a secret that shipped or
a diagram that coloured a failure state green.

The harness closes it in four layers.

## The layers

| Layer | What it does | Deterministic? |
|-------|--------------|----------------|
| **1 · Structural** | Frontmatter is present and well-formed; `name` matches the path | Yes |
| **2 · Referential** | Every agent a skill spawns exists; every agent is spawned by something; every `§` citation resolves | Yes |
| **3 · Class contract** | A skill honours the promises of the class it declares | Yes |
| **4 · Behavioural** | The skill actually leaves no files, makes no commit, spawns no agent when it must not | **No — needs a real run** |

Layers 1–3 are `check.sh`: pure text analysis, about a second, no model involved.
Layer 4 is `tests/`, and it is the one that costs money — which is why it is split in
two.

## Why layer 4 is split

`tests/run.sh` spawns real skills against disposable fixture repos and records what
happened. It spends money, so it runs locally and deliberately.

`tests/assert.sh` reads those committed snapshots back and checks them. No model, no
cost — so **that** is what CI runs, on every push.

The split is what makes behavioural assertions affordable at all.

## What it cannot check

Worth stating plainly, because a harness that implies more coverage than it has is
worse than none:

- **Only negative contracts.** *"Left no files"*, *"made no commit"*, *"spawned no
  agent"* are filesystem and process facts. *"Found the right bugs"* needs a model to
  judge and is out of scope.
- **Snapshots are point-in-time.** They record what a skill did on the day
  `run.sh` ran, not what it would do today.
- **Prose discipline is unenforceable.** *"Halt on any signal to stop"* is a rule for
  the model. Nothing mechanical can verify it was obeyed.

## Forward coverage

The part that matters most: the harness binds **skill #24**, not just the ones that
exist today.

Everything globs `skills/*/` and `agents/*.md` rather than reading a registry, so a
skill added tomorrow is covered the moment its directory exists. There is no
registration step to forget — which is the same class of bug the harness exists to
catch, and it would be embarrassing to reproduce it inside the catcher.
