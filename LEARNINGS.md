# Learnings & improvement backlog

Field notes from driving these skills and agents through a long, real session
(building and shipping the **Relayent** project: a multi-tenant AI-relay — blog
post, architecture + security diagrams, screenshots, code review, and a live
prod deploy). Every item below is grounded in something that actually happened —
a wall hit, a workaround improvised, or an assumption that didn't hold — not a
hypothetical. Ordered by impact.

Legend: **[P1]** high-impact / recurring · **[P2]** worth doing · **[P3]** nice-to-have.

---

## Cross-cutting

### [P1] Diagram generation must render-and-verify before returning
The single biggest weakness observed. `arch-diagram` / `diagram-architect`
produced a system diagram so crowded it was unusable — overlapping text, connector
lines routed straight through boxes, annotation boxes colliding with their own body
text. The root cause: **diagrams are emitted as SVG/Excalidraw and returned without
ever being rendered and inspected.** Overlaps are invisible in the source; they only
appear on screen.

Every diagram that ended up usable this session did so only after: render to an
image (headless browser or an export step) → screenshot → visually check for
overlaps/legibility → fix → repeat. That loop should be **built into the skill**,
not left to the operator to reinvent.

- **Change:** after emitting a diagram, the skill/agent should render it (Playwright
  on an HTML wrapper, or `npx excalidraw_export`, or the Excalidraw MCP) and
  self-check: do bounding boxes of text/nodes overlap? Is any label outside the
  canvas? Are connectors crossing node interiors? Only return once clean.
- **Bonus:** a simple overlap heuristic (compare element bounding boxes) catches
  90% of the failures cheaply, before even rendering.

### [P1] Skills assume tools "just run" — handle sandbox/permission denials gracefully
In this environment, several tool calls were **blocked by a permission classifier**:
SSH to the prod host, and the screenshot **capturer subagent** on its first attempts.
The skills have no notion of "the tool I need was denied," so the orchestrator had to
notice the denial and improvise a fallback each time.

- **Change:** where a skill depends on an action that can be denied (network egress,
  SSH, spawning a browser subagent, writing outside an allowed root), it should
  detect the denial and **degrade to a documented manual path** — e.g. "print the
  exact commands for the user to run," or "ask the user to supply the artifact" —
  rather than failing or silently stalling.

### [P2] Give authoring skills a first-class scratch/preview workspace
Repeatedly needed a place to render-and-inspect (SVG previews, HTML wrappers, base64
data-URIs) that is neither the repo nor an ad-hoc `/tmp` path. Playwright can also
**only write under the repo root**, which fought the "gitignored raw dir" plan.

- **Change:** standardize a preview/scratch convention the skills reference, and make
  screenshot/diagram steps aware of the browser tool's write-root constraint.

---

## tech-blog (skill + writer / fact-checker / reviewer / editor / poster)

**What worked — keep it.** The pipeline is genuinely strong. The **fact-checker's
blocking gate is the standout feature**: it caught claims carried over verbatim from a
prior draft (the writer reused fact-checked quotes without re-reading source) and
forced independent re-verification against the actual `.go` files. It also held the
"cost claim must stay qualitative — no invented numbers" line. Do not weaken this.

### [P1] No "revise an existing post" path
The post was reframed **twice** (angle change, then positioning change) and lightly
edited several more times. Each time, the only route was to re-run
writer → fact-checker → editor by hand. There is no first-class *revision* mode.

- **Change:** add a revision entry point that takes an existing post + a change
  request, re-runs only the fact-checker on changed claims, and applies the edit —
  instead of a full regeneration.

### [P2] Warn about platform-relative image paths
The editor emits repo-relative image links (`./images/…`, `../architecture/…`).
Those render on GitHub but **silently break on dev.to** (and most external CMSs),
which need absolute URLs or platform-uploaded images. This wasn't surfaced; it was
discovered by reasoning about it.

- **Change:** when a publish target is external (dev.to/Medium/etc.), the skill
  should flag relative image paths and offer to rewrite them to absolute (e.g. raw
  GitHub URLs) or note that images must be uploaded to the platform.

### [P2] Voice defaults to "AI-symmetric" until asked otherwise
The first drafts had the tell-tale tidy tricolons, over-balanced "not X but Y"
constructions, and relentless symmetry. It only read like a human practitioner after
an explicit "sound less AI, like an experienced architect" instruction.

- **Change:** expose a `voice`/`persona` parameter (e.g. "practitioner, first-person,
  varied sentence length, opinionated") and default toward it, or have the reviewer
  explicitly flag AI-symmetry as a finding.

### [P3] Publish-ready HTML/preview isn't produced by default
A standalone, self-contained HTML render (images inlined as data-URIs) was invaluable
for "review it like a blog before posting." It was built ad hoc each time.

- **Change:** make a self-contained HTML/preview a standard pipeline output alongside
  the Markdown.

---

## arch-diagram / diagram-architect — biggest single target

See the **[P1] render-and-verify** item at the top; it applies here first and hardest.

### [P1] Support a "conceptual" mode, not only repo-structural
The agent is built to **diagram the real repo** ("every element traces to the actual
repo; nothing is invented"). That's perfect for a system-architecture map — and it
produced a good one. But a **trust-boundary / conceptual** diagram (for the blog's
security section: "where is data encrypted vs. in the clear") is not a component map,
and the grounding mandate actively fought it.

- **Change:** add an explicit `conceptual` vs `structural` mode. Conceptual mode
  relaxes the repo-grounding rule (the *facts* still must be true, but the boxes are
  ideas, not modules) and leans on hand-layout / the Excalidraw MCP.

### [P2] Prefer the Excalidraw MCP as a render path when connected
`npx excalidraw_export` **failed on the prod box** (npm registry/tarball errors), so
the SVG fell back to agent-emitted. Meanwhile the **Excalidraw MCP** (when connected)
renders reliably with draw-on animation and returns an editable excalidraw.com link —
a strictly better authoring loop.

- **Change:** detect the Excalidraw MCP and prefer it for rendering + editable-link
  output; keep `npx` export as the fallback, not the default.

### [P2] Emoji-in-SVG needs a render check
A 🔒 in an SVG `<text>` rendered fine in the browser here, but the Excalidraw read_me
explicitly warns emoji don't render in its font, and cross-renderer support is
uneven. The verify step should confirm any emoji/glyph actually paints (no tofu).

---

## pre-push-review (+ correctness / secrets / tests-build / style / dependency)

**What worked — the most trustworthy skill in the set.** Run on a real
session-authenticated `/v1/me` endpoint change: the secret-gate-first ordering,
parallel dimensions, and clean PASS/WARN aggregation all behaved exactly as designed.
The **secrets-reviewer** confirmed the authz/self-scoping was sound; the
**style-reviewer** caught a real hygiene miss (two new files missing the repo's
standard `// Created on:` / `// Last updated:` header lines) that would otherwise have
shipped. High signal, low noise.

### [P2] Handle the "branch already pushed" scope case
The skill's "unpushed changes" scope came up empty because the branch had **already
been pushed** before review. The scope had to be manually set to `main..HEAD`.

- **Change:** treat "already-pushed feature branch, review vs. merge-base with the
  default branch" as a first-class scope, not only "staged + unstaged + unpushed."

### [P3] Dependency dimension correctly no-ops on no-manifest-change
Minor positive: with no manifest changes, skipping the dependency dimension was the
right call — keep that behavior explicit so it's not mistaken for a gap.

---

## capture-screenshots (+ capturer / sensitive-data-reviewer / redactor)

**What worked — the redaction discipline is excellent and did its job.** A real
personal email surfaced in an admin-console screenshot; the pipeline flagged it and
the substitution/redaction produced a clean, natural-looking result with the original
never committed. The verify-before-write gate is the right shape.

### [P1] The capturer needs a real fallback when it can't capture
Two concrete failures: (a) the **capturer subagent was classifier-blocked** on first
attempts; (b) **auth-gated pages** (the `/admin` console behind OIDC) can't be
captured without credentials the skill shouldn't fabricate. The skill assumes it can
always get the shot.

- **Change:** add explicit branches — "capturer blocked → fall back to direct browser
  tools or ask the user to supply the image," and "target is behind login → offer a
  'you capture, I redact' path" rather than attempting to obtain credentials.

### [P2] Codify the browser write-root constraint
Playwright could only write screenshots **under the repo root**, not an arbitrary
scratch path — this caused a failed write mid-run. The skill's gitignored-raw-dir plan
is correct but should account for where the browser tool is actually allowed to write.

### [P3] "Substitute a realistic placeholder" is a great low-risk redaction default
For low-risk illustrative PII (an email), replacing it with `demo-admin@example.com`
read far better in a blog than a black box. Worth promoting from ad-hoc to a
documented redaction style alongside blur/box.

---

## Meta

The most reusable lesson across everything: **generation is cheap; verification is
what makes output trustworthy.** The skills that already bake verification in
(fact-checker's blocking gate, redactor's coverage gate, pre-push-review's secret
gate) are the ones that performed best with the least babysitting. The ones that
emit-and-return without a verify loop (diagram generation, screenshot capture under
constraints) are where all the rework happened. Push every skill toward
"produce → render/inspect → gate → return."
