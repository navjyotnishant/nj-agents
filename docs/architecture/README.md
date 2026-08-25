# Architecture diagrams

Authored directly as SVG by [`/arch-diagram`](../../skills/arch-diagram/SKILL.md) —
infographic style by default, `--sketch` for a hand-drawn variant. Each one is
rendered and reviewed against a 15-second readability test before it ships.

Everything here is grounded in the actual `skills/*/SKILL.md` and `agents/*.md`
definitions. Counts are verified against the repo before they are drawn: a wrong
number in the most glanceable part of a diagram discredits everything around it.

## The toolkit

| Diagram | What it shows |
|---|---|
| [`suite-overview.svg`](./suite-overview.svg) | The five classes and what each one promises about what it will and will not touch |
| [`agents-overview.svg`](./agents-overview.svg) | How skills and agents relate — one level deep, always |
| [`harness.svg`](./harness.svg) | The verification harness: what is checked, by what, and where |

## Pipelines

One per skill that spawns more than one agent, showing the dispatch order and any
blocking gate.

| Diagram | Agents |
|---|---|
| [`pipeline-tech-blog.svg`](./pipeline-tech-blog.svg) | 9 — a 7-stage pipeline whose fact-checker BLOCKs unverifiable claims |
| [`pipeline-pre-push-review.svg`](./pipeline-pre-push-review.svg) | 5 — a secret gate first, alone, then a parallel fan-out |
| [`pipeline-capture-screenshots.svg`](./pipeline-capture-screenshots.svg) | 3 — detect, redact, then verify coverage before writing |
| [`pipeline-docs-site.svg`](./pipeline-docs-site.svg) | 2 |
| [`pipeline-deps-upgrade.svg`](./pipeline-deps-upgrade.svg) | 2 |
| [`pipeline-test-gap-finder.svg`](./pipeline-test-gap-finder.svg) | 2 |

`pipeline-tech-blog.sketch.svg` is the same diagram in the `--sketch` style, kept as
a reference for what that variant looks like.

## Workflow-tool pipelines (model-generated PNG)

The three skills built on the `Workflow` tool (scripted `agent()`/`pipeline()`/
`parallel()`/`phase()` orchestration, not the informal "spawn N agents" prose the
rest of this repo uses) get their own diagrams — generated from a detailed prompt
via Nano Banana rather than hand-authored SVG, since these illustrate a scripted
control-flow shape (retry loops, phase barriers, schema-typed data passing between
stages) that reads more naturally as an infographic than as `/arch-diagram`'s
component-relationship style.

| Diagram | What it shows |
|---|---|
| [`pipeline-security-deep-review.png`](./pipeline-security-deep-review.png) | Find (5 parallel lens finders) → Verify (3 adversarial verifiers per finding, majority-refute kills it) → Synthesize, with the mandatory secret-scan gate before Find |
| [`pipeline-pre-push-review-nano.png`](./pipeline-pre-push-review-nano.png) | Secret Scan Gate → 5 dimensions in parallel (Dependencies shown SKIPped when no manifest changed) → plain-JS aggregation → optional `review-report-writer` |
| [`pipeline-tech-blog-nano.png`](./pipeline-tech-blog-nano.png) | Draft (writer + a bounded fact-check retry loop, max 2 rounds) → Refine (reviewer, editor) → Finalize (final-polish + platform-lint in parallel, converging to a serialized apply outside the script) |

## Editing

The SVG diagrams above are hand-authored, not generated from a model — edit the SVG
directly, then **render and look at it** before committing:

```bash
rsvg-convert -w 1400 docs/architecture/<name>.svg -o /tmp/<name>.png
```

Source review cannot catch a label hidden behind a stroke, an arrowhead removed by a
filter, or a count that disagrees with the shapes beside it. Only rendering it can.

The three Workflow-tool PNGs are model-generated from a text prompt instead —
regenerate from an updated prompt rather than hand-editing the PNG if the underlying
pipeline shape changes.

The full browsable reference lives at
[navjyotnishant.github.io/nj-agents](https://navjyotnishant.github.io/nj-agents/).
