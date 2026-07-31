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

## Editing

These are hand-authored SVG, not generated from a model — edit the SVG directly, then
**render and look at it** before committing:

```bash
rsvg-convert -w 1400 docs/architecture/<name>.svg -o /tmp/<name>.png
```

Source review cannot catch a label hidden behind a stroke, an arrowhead removed by a
filter, or a count that disagrees with the shapes beside it. Only rendering it can.

The full browsable reference lives at
[navjyotnishant.github.io/nj-agents](https://navjyotnishant.github.io/nj-agents/).
