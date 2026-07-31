---
name: scaffold-project
description: Use this skill when the user asks to "scaffold a new project", "set up a new repo properly", "bootstrap a project to industry standards", "start a new service/library/app", or wants a greenfield repository laid out to a recognized baseline. Grounds the security/governance layer in the OpenSSF OSPS Baseline (cited by control ID, Level 1 by default) and delegates the stack-specific layout to the ecosystem's own generator (cargo new, uv init, npm create) rather than inventing one. Reads a supplied project doc first when there is one. Verifies the result against the baseline before reporting done, then PROPOSES the commit. Works for any stack; nothing here is project-specific.
version: 0.1.0
class: authoring
author: navjyotnishant
---

# Scaffold Project (authoring)

Lays out a **new** repository to a recognized industry baseline. Every other skill in
this suite reacts to code that already exists; this one runs when there is little or
nothing there yet, so its grounding rules are necessarily different — see
**Grounding** below.

Shared authoring rules: `CONVENTIONS-authoring.md` (§A2 scoped output, §A3
propose-commit, §A4 placement, §A5 MCP-detect-never-require, §A6 grounding,
§A7 idempotent). It **writes files but never commits** (§A3).

> **Finding the conventions file.** It lives at the toolkit repo root, two levels
> above this skill — not beside `SKILL.md`. Skills are usually installed as
> symlinks into your runner's skills directory, so a plain relative path resolves against the
> *link* and misses it. Resolve the link first:
>
> ```bash
> ROOT="$(dirname "$(readlink -f "<this skill's base directory>")")/.."
> ```
>
> then read `$ROOT/CONVENTIONS-authoring.md`. If a file is genuinely absent, say so and continue
> with the procedure below rather than stopping.

> **Every skill follows `CONVENTIONS-orchestration.md` §U** — ground everything in
> the actual repo, never run git on your own initiative, no secrets in output,
> keep `CHANGELOG.md` current when the change is user-facing, degrade rather than
> fail, and say what you did not do.

---

## Dependencies

Detected at runtime, never installed by this skill (`§A5`).

| Tool | Used for | Without it |
|---|---|---|
| the ecosystem's own generator (`cargo new`, `uv init`, `npm create`) | laying out the stack-specific structure | a minimal hand-written layout — say which parts the generator would normally have provided |
| `gitleaks` | wiring the secret-scanning pre-commit hook (`OSPS-BR-07.01`) | the hook is scaffolded but noted as inactive until a scanner is installed |

## Grounding — where the standard comes from (READ FIRST)

§A6 says *never invent*. With no repo to read, this skill grounds in **three external
sources** instead, and cites which one every file came from:

| Layer | Source of truth | Never |
|---|---|---|
| Security & governance | **OpenSSF OSPS Baseline** — cite the control ID (`OSPS-LE-03.01`, …) | Invent a "best practice" with no control behind it |
| Stack layout (`src/`, manifest, test dir) | **The ecosystem's own generator** — `cargo new`, `uv init`, `npm create vite`, `go mod init`, `dotnet new` | Hand-roll a directory layout the ecosystem doesn't use |
| Project specifics (name, purpose, components) | **The user's project doc**, when supplied | Guess the domain, invent components |

If a requested file traces to none of the three, **say so and ask** rather than
producing it. "Industry standard" is a claim; it needs a citation.

**Default target: OSPS Baseline Level 1.** Level 1 is the solo/early-project tier.
Offer Level 2 only if the user says the project is published, multi-maintainer, or
distributed as a package — do not silently upgrade, as Level 2 pulls in signed
releases and a disclosure policy with response timeframes.

---

## Step 1 — Banner

Print before touching anything:

```
scaffold-project: I'll set up this repository to the OpenSSF OSPS Baseline
(Level 1 by default), delegating stack layout to the ecosystem's own generator.
I write files and PROPOSE the commit — I never commit, push, or tag.
```

## Step 2 — Ingest the project doc (primary grounding)

**The user usually supplies a project doc with the request.** It is the highest-value
input — read it before asking anything.

1. Read whatever they supplied (path, pasted text, or an attached file).
2. Extract: **project name, purpose, stack/language, major components, intended
   audience, distribution** (internal tool? published package? service?), and any
   constraints (license, org conventions, compliance).
3. Extract the **distribution** signal especially — it decides Level 1 vs 2.

Then read whatever already exists on disk (§A1): an existing `README`, a manifest, a
partial tree. **Scaffolding is not always empty-directory work** — the user may be
retrofitting a repo that already has code.

**Only ask about what the doc genuinely does not answer.** Do not re-interrogate the
user on facts their doc already states. If no doc was supplied, ask for the minimum:
name, language, and whether it will be published.

## Step 3 — Confirm the plan before writing

Show a compact plan and get agreement. Two things must be explicit:

- **Tier** — Level 1 (default) or Level 2, with the reason.
- **Generator command** — the exact ecosystem command you intend to run, if any.

```
Project:    <name> — <one-line purpose>          [from: project doc]
Stack:      <language/framework>                 [from: project doc]
Tier:       OSPS Baseline Level 1
Generator:  uv init --lib                        [ecosystem tool]
Adds:       LICENSE (OSPS-LE-03.01), SECURITY.md (OSPS-VM-02.01),
            CONTRIBUTING.md (OSPS-GV-03.01), .gitignore + secret-scan
            pre-commit (OSPS-BR-07.01), CI w/ tests (OSPS-QA-06.01),
            issue guidance (OSPS-DO-02.01), CLAUDE.md
Existing:   <files already present — will not be overwritten>
```

**Never overwrite an existing file** (§A2/§A7). Report it as `exists — left alone`,
or offer to merge additively. This makes the skill safe to re-run on a partial repo.

## Step 4 — Run the ecosystem generator (stack layer)

Detect the tool for the chosen stack and **run the real thing** rather than emulating
its output — that is what makes the layout idiomatic instead of invented:

| Stack | Command |
|---|---|
| Python | `uv init` (or `poetry new`) |
| Rust | `cargo new --lib` / `--bin` |
| Node/TS | `npm create vite@latest` / `npm init -y` |
| Go | `go mod init <module>` |
| .NET | `dotnet new <template>` |

**Detect, never require** (§A5). If the tool is absent, say which one and why it would
help, then fall back to a minimal hand-written manifest — and **mark that layer
"unverified against the ecosystem standard"** so the gap is visible, not silent.

`git init` only if the directory is not already a repo.

## Step 5 — Layer the OSPS Baseline files (governance layer)

Write only what is missing. Each file carries its control ID in the plan output, not
in the file itself (don't litter generated files with control numbers).

**Level 1 set:**

- **LICENSE** — `OSPS-LE-03.01`. **Ask which license**; never assume. If the project
  doc names one, use it. Write the full canonical text, not a stub.
- **SECURITY.md** — `OSPS-VM-02.01`. Security contact + how to report privately.
- **CONTRIBUTING.md** — `OSPS-GV-03.01`. How to propose a change; reference the
  repo's actual test/build commands, discovered not invented.
- **README.md** — purpose, install, usage, license. Grounded in the project doc.
- **.gitignore** — ecosystem-appropriate; must cover secret-bearing paths
  (`.env`, credentials) per `OSPS-BR-07.01`.
- **Secret-scanning pre-commit hook** — `OSPS-BR-07.01`. Wire `gitleaks` if present.
  This suite's own `/review-secrets` enforces the same control later.
- **CI workflow** — `OSPS-QA-06.01` (Level 2 formally, but cheap and worth it at
  setup): run the project's test command on push/PR. Pin actions by version.
- **Issue/defect reporting guidance** — `OSPS-DO-02.01`; issue templates or a README
  section.

**CLAUDE.md** — not an OSPS control; it is the agent-legibility layer from Anthropic's
Claude Code guidance. Keep it **lean and layered — under ~200 lines**; document build
and test commands, layout, and conventions. Cite it as such, not as a baseline
control.

**Level 2 adds** (only when the user opted in): signed releases + hashed manifest
(`OSPS-BR-06.01`), a changelog per release (`OSPS-BR-04.01` — this suite's
`/changelog` produces it), a coordinated disclosure policy with response timeframes
(`OSPS-VM-01.01`), and dependency pinning (`OSPS-BR-05.01`).

## Step 6 — Verify against the baseline (GATE, do not skip)

**The scaffold is not done when the files are written — it is done when it verifies.**
Asserting compliance without checking it is exactly the invention §A6 forbids.

1. **Automated, when available:** run **OpenSSF Scorecard** if it is on PATH
   (`scorecard --local .`). It checks License, Security-Policy, Pinned-Dependencies,
   CI-Tests, Token-Permissions among others. Detect, never require (§A5).
2. **Always, as the floor:** walk the Level 1 controls and confirm each is genuinely
   satisfied — file present *and* non-placeholder. A `SECURITY.md` reading
   "TODO: add contact" does **not** satisfy `OSPS-VM-02.01`.
3. **Confirm the generator's output actually appeared** — a manifest and test dir
   exist, and the test command runs.

Report a per-control table: **control ID → satisfied / gap → the file**. Anything not
met is reported as a **gap the user must close**, never quietly rounded up to done.
If Scorecard was unavailable, say which controls were checked by hand.

## Step 7 — Propose the commit (§A3)

Show `git status --short` and `git diff --stat`, then print the copy-paste block:

```bash
git add <paths>
git commit -m "chore: scaffold project to OSPS Baseline Level 1"

git push
```

**Never run git yourself.** For a brand-new repo, note that the first push needs a
remote and that `main` should get branch protection (Scorecard's `Branch-Protection`)
— that is a settings change on the forge, not something this skill can do.

---

## Report format

```
## Scaffold — <project> (OSPS Baseline Level 1)

Grounding:  project doc <path> · OSPS Baseline · <generator> 
Created:    <files>
Left alone: <pre-existing files>

| Control        | Requirement            | Status | File          |
|----------------|------------------------|--------|---------------|
| OSPS-LE-03.01  | License present        | ✅     | LICENSE       |
| OSPS-VM-02.01  | Security contact       | ✅     | SECURITY.md   |
| OSPS-BR-07.01  | No plaintext secrets   | ✅     | .gitignore +  |
|                |                        |        | pre-commit    |

Verified by: scorecard --local .   (or: checked by hand — scorecard not installed)

Gaps: <anything unmet, or "none">
Next: branch protection on `main` (forge setting, not scaffolded here).
```

## Safety rails

- **Never commit, push, or tag** (§A3). Never `--no-verify`.
- **Never overwrite an existing file**; report and skip, or merge additively (§A7).
- **Never claim a control is met without checking it** — cite the file that satisfies
  it, or report the gap.
- **Never invent a "standard"** — every governance file traces to a control ID, every
  layout decision to the ecosystem generator, every project fact to the user's doc.
- **Ask for the license**; do not assume one.
- OSPS Baseline is **security/governance-focused**. It says nothing about internal
  code layout — that is the generator's job. Don't stretch it to cover architecture.
