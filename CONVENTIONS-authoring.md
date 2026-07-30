# nj-agents — shared authoring conventions

The **authoring class** of skills (`changelog`, `arch-diagram`, `tech-blog`) is the
counterpart to the review class in `CONVENTIONS.md`. Where review skills *advise only
and leave no files*, authoring skills **write artifacts into the repo** — a
changelog, a diagram, a blog post. This document holds the rules they share so each
`SKILL.md` references it instead of repeating them. When an authoring skill says
"ingest per §A1" or "propose the commit per §A3," this is what it means.

The one rule both classes share: **the human decides what gets committed.** Authoring
skills write files, but they never `git commit`, `push`, or `tag` — they propose.

---

## §A1 — Repo-context ingest (shared)

Before generating anything, build an in-memory **repo model** so the output is
grounded in what actually exists (never invented — see §A6).

1. Find the repo root: `git rev-parse --show-toplevel`.
2. Read, in priority order (skip what's absent):
   - `README*`, `ARCHITECTURE.md`, `docs/` — especially `docs/architecture/`,
     `docs/adr/`, `docs/decisions/`, design docs.
   - `CLAUDE.md` / `AGENTS.md` / `CONTRIBUTING.md`.
   - Top-level package manifests (`package.json`, `pyproject.toml`, `go.mod`,
     `Cargo.toml`, etc.) for name, stack, entry points.
   - The directory tree, ~2 levels deep, for module/component layout.
3. Summarize into a repo model: **name, purpose, stack, key components, entry points,
   public API surface, notable docs/ADRs.**

**Cap large repos.** Don't read everything — sample the most significant files
(entry points, top-level modules, the main docs) and **note what you did not read**
so the output's scope is honest. Keep the model in memory or the scratchpad/temp dir
— **never write it into the repo tree.**

---

## §A2 — Authoring output is allowed (but scoped)

Unlike review-class skills, authoring skills **do write files into the repo tree** —
but only the specific artifact requested (the changelog, the diagram + its embed, the
blog post), at the path resolved by §A4. Never modify unrelated files. Never
reformat, "clean up," or touch code the user didn't ask about.

---

## §A3 — Propose the commit, never auto-commit (shared)

After writing the artifact, **always**:

1. Show what changed:
   ```bash
   git status --short
   git diff --stat
   git diff -- <the-paths-you-wrote>
   ```
2. Print a copy-paste block the user runs themselves:
   ```bash
   git add <paths>
   git commit -m "<suggested conventional-commit message>"
   git push
   ```
   (`git push` on its own line so it's a separate, conscious action.)

**Never run `git add` / `git commit` / `git push` / `git tag` yourself.** This holds
in non-interactive/CI mode too: write the artifact, print the commands, stop. The
human (or their own automation) decides. Never use `--no-verify`, and never bypass a
pre-push gate (the review suite may be wired as one).

If the artifact went somewhere gitignored or outside the repo, say so instead of
printing a commit block.

---

## §A4 — Placement resolution (shared)

Deterministic ladder for "where does this file go":

1. **Existing canonical location** for this artifact type (an existing
   `CHANGELOG.md`, `ARCHITECTURE.md`, `docs/architecture/`, `docs/blog/`) — merge
   into it per §A7.
2. Else the **conventional path**: `CHANGELOG.md` at repo root; diagrams in
   `docs/architecture/`; blog posts in `docs/blog/<slug>.md`.
3. Else **propose creating it** — ask in interactive mode; use the conventional
   default in non-interactive mode.

Always **report the chosen path and why**, before or with the write.

---

## §A5 — MCP detected, never required (shared)

Some outputs can use an MCP connector (Figma for diagrams, a CMS/Notion/Dev.to
connector for blog posting). **Probe for these at runtime and use them only if
present.** Every authoring skill has a **zero-dependency fallback** that produces a
usable local artifact (a `.excalidraw`+`.svg`, a publish-ready `.md`/`.html`).

Never hard-require an MCP connector, and never assume a non-PATH CLI is installed
(no assumed `mmdc`, `plantuml`, `dot`, `d2`). If a helpful CLI *is* on PATH (e.g.
`npx`, `pandoc`), it may be used; if not, degrade gracefully and say so.

---

## §A6 — Ground everything / safety (shared)

- **No invented facts.** Every component, API, endpoint, config key, or feature named
  in generated output must trace to the §A1 repo model or to something read from the
  repo. If unsure, say "not found in the repo" rather than fabricating.
- **No secrets in output.** Never embed a credential, token, internal hostname, or
  private URL into a changelog, diagram, or blog. If the source docs contain one,
  omit or redact it.
- **Respect `.gitignore`** and existing repo structure. Don't create a competing
  docs system when one exists.
- **Never `--no-verify`**; never bypass the review/pre-push gate.

---

## §A7 — Idempotent / non-clobber (shared)

Re-running an authoring skill must **merge, not destroy**:

- Changelog: add to the existing `[Unreleased]` section; never rewrite released
  sections.
- Diagram: update the existing diagram file and its embed in place; keep the same
  path/filename so the doc link doesn't break.
- Blog: if a post with the same slug exists, treat it as a revision — show a diff and
  confirm, don't silently overwrite.

Always show a diff of what changed; never silently replace an existing artifact.

---

## §A8 — Degrade gracefully when a tool is denied or unavailable (shared)

Skills run in varied environments. A tool call you depend on may be **denied by a
sandbox/permission classifier**, not just missing — this happened in practice with SSH
to a host, a browser subagent loading a live URL, and writes outside an allowed root.
Treat a denial the same as a missing tool: **detect it, degrade, and keep going** —
never fail silently or stall.

- **Detect the denial** (a permission error, a blocked-by-classifier message, a
  refused write path) rather than retrying the identical call in a loop.
- **Degrade to a documented manual path.** If you can't run it, hand the user the
  exact commands to run themselves, or ask them to supply the artifact the step would
  have produced (an image, a file), then continue the pipeline from there.
- **Try a narrower equivalent first.** A denied subagent spawn may still work as a
  direct tool call; a refused write outside the repo may succeed inside it (then move
  the file). Prefer the reasonable in-bounds path over abandoning the step.
- **Never work around the intent of a denial** — don't fabricate credentials, bypass
  auth, or route around a security control to accomplish the task. A denial about
  *safety* is a stop; a denial about *capability* is a detour.
- **Say what you did.** Note in the summary that a step was degraded/manual so the
  result isn't mistaken for a full automated pass.

---

## Spawning subagents

If a skill in this class spawns subagents, `CONVENTIONS-orchestration.md` also
applies: **§C** (state the cost shape before spawning, cap fix rounds at 2, halt on
any signal to stop) and **§R** (announce the agent roster before dispatch, mark each
one as it lands). Those rules are class-agnostic — a six-agent pipeline costs the
same whatever it produces.
