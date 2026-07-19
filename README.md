# nj-agents

A personal, project-agnostic collection of Claude Code **skills and agents** for
software-development workflows. Maintained independently and installed into any
project (or globally) via symlink. Designed to grow — new skills/agents drop into
`skills/` and `agents/` and are picked up on the next install.

## What's in here today

A **pre-push review suite**: a thorough, AI-assisted review of your *current commit
or uncommitted changes* before you push (or any time, on demand, or from CI). Five
review dimensions, each a dedicated skill + agent pair, plus one umbrella that runs
them all.

| Skill | What it does | Agent it uses |
|---|---|---|
| `/pre-push-review` | **Umbrella.** Prints the warning banner, runs the secret scan as a gate, then spawns the other dimensions in parallel and aggregates one PASS / WARN / BLOCK verdict + a report artifact. | (orchestrates the below) |
| `/review-secrets` | Secret scan over the diff **first** (hard gate — shares nothing if a key is found): a dedicated scanner (gitleaks/trufflehog/detect-secrets) if installed, else a model-reasoned fallback. Then a semantic security pass. | `secrets-reviewer` |
| `/review-correctness` | Bugs, regressions, edge cases, missing validation in the changed lines and their blast radius. | `correctness-reviewer` |
| `/review-tests-build` | Auto-detects and runs the repo's own test/lint/build commands as a gate. Never installs tooling. | `tests-build-runner` |
| `/review-dependencies` | Added/removed/upgraded packages, version-pinning risk, license changes, supply-chain signals (typosquatting). Diff-only; no network, no install. | `dependency-reviewer` |
| `/review-style` | Consistency with surrounding code, commit-message hygiene, leftover debug/TODO output. | `style-reviewer` |

Each dimension runs standalone; the umbrella runs them together. Shared behavior
(snapshot scope, diff hygiene, findings format, CI mode, report artifact, safety
rails) lives once in [`CONVENTIONS.md`](CONVENTIONS.md).

## ⚠️ What it does with your code — read this

These review skills **generate a snapshot of your changes** (the `git diff` of your
staged, unstaged, and committed-but-unpushed work) and **share it with AI** — the
Claude session running the skill, plus the subagents it spawns — to review it. **No
external API is called**; the current session does the analysis. Every skill prints
a banner saying so before it reads anything.

**A local secret scan runs before any snapshot is shared.** If a credential, key,
or token is detected in the diff, the review **stops and shares nothing** until you
remove it.

The suite **advises only**. It never pushes, never commits, never bypasses git
hooks, and leaves no files in your repo.

## Prerequisites

- **Claude Code**, and a **git repository** to review (`git` on PATH).
- **A diff to review** — if there's nothing staged/unstaged/unpushed, the skills
  stop cleanly.
- **No API key required, no network** — the review uses your current Claude session.
- **Recommended:** a dedicated secret scanner on PATH — [`gitleaks`](https://github.com/gitleaks/gitleaks),
  `trufflehog`, or `detect-secrets`. `review-secrets` prefers it for authoritative
  detection and falls back to a model-reasoned scan if none is installed (and tells
  you which ran). For enterprise use, install one.
- **Optional:** a test/lint/build command. `review-tests-build` auto-detects it
  (Node/Python/Go/Rust/JVM/Make/just, or a command documented in
  `CLAUDE.md`/`AGENTS.md`). If none exists, that dimension reports SKIP — it never
  invents or installs one.

## Data handling / privacy

Nothing leaves your machine. The suite reads your git diff and analyzes it with the
**Claude session already running** — no external API is called, no third-party
service receives your code. Before any diff is shared even with a subagent, the
secret scan runs; on a hit it stops and shares nothing. Report artifacts are written
outside the repo tree (or under a gitignored dir) and contain **no unmasked
credentials**. See [`CONVENTIONS.md`](CONVENTIONS.md) §3/§6/§7.

## CI / non-interactive use

Set `NJ_AGENTS_CI=1` (or pass `--ci`) to run without prompts, suitable for a
pipeline or git hook. In CI mode the review never waits for confirmation — any
ambiguity resolves to the safe (BLOCK) outcome — and honors an **exit-code
contract**: `0` for PASS/WARN, non-zero for BLOCK. A wired hook or CI step keys off
that code. The suite itself still only advises — it never runs `git push` and never
bypasses a hook.

## Report artifact

Each umbrella run writes a timestamped record — repo, branch, scope reviewed, which
secret scanner ran, files excluded, per-dimension verdicts + findings, and the
aggregate verdict — to `${NJ_AGENTS_REPORT_DIR:-<repo>/.nj-agents-reports}/` (or the
temp dir). It is **never committed**; the umbrella offers to add
`.nj-agents-reports/` to your `.gitignore`.

## Install

Global (all projects):

```bash
./install.sh
```

Per-project (into `DIR/.claude/`):

```bash
./install.sh --project /path/to/your/repo
```

Uninstall (only removes symlinks pointing back into this repo):

```bash
./install.sh --uninstall
./install.sh --project /path/to/your/repo --uninstall
```

Restart / reload Claude Code afterward, then run `/pre-push-review` in any repo.
The installer uses **symlinks**, so editing files here updates every install.

## Optional: gate on `git push`

By default the suite is **manual / on-demand** — nothing auto-fires. If you want it
to gate an actual push, wire one of these **per project** (never globally, and the
suite proposes it, never installs silently):

- **Native git hook** — a `.git/hooks/pre-push` that runs the review and exits
  non-zero on BLOCK. Gates any push by anyone; `git push --no-verify` remains a
  conscious, visible bypass.
- **Claude Code `PreToolUse` hook** — in the project's `.claude/settings.json`,
  matching `Bash(git push*)`, to gate pushes made *through Claude*.

Run `/pre-push-review` and it will offer to set one up.

## Layout

```
nj-agents/
├── skills/<name>/SKILL.md   # each skill is a directory + SKILL.md
├── agents/<name>.md         # each agent is a flat .md
├── CONVENTIONS.md           # shared review rules referenced by every skill
├── install.sh               # symlinks skills/ + agents/ into a .claude/ dir
└── README.md
```

## Adding more

Drop a new skill directory under `skills/` (with a `SKILL.md`) or a new agent `.md`
under `agents/`, then re-run `./install.sh`. Keep everything **project-agnostic** —
discover per-repo details at runtime rather than hardcoding a stack, path, port, or
tool.
