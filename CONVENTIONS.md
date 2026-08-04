# nj-agents — shared review conventions

Every review skill in this repo follows these shared rules. Individual `SKILL.md`
files reference this document instead of repeating it. When a skill says "build the
snapshot per CONVENTIONS.md" or "apply diff hygiene per CONVENTIONS.md," this is
what it means.

---

## 1. Snapshot scope (what "the changes" means)

The reviewable delta is everything **not yet on the remote**, assembled with plain
git only (no stack assumptions):

```bash
git diff --cached                          # staged
git diff                                   # unstaged
UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null)
if [ -n "$UPSTREAM" ]; then RANGE="$UPSTREAM..HEAD"; else
  DEFAULT=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
  RANGE="${DEFAULT:-HEAD}..HEAD"
fi
git diff "$RANGE"                          # committed-but-unpushed
git log "$RANGE" --format='%h %s%n%b'      # unpushed commit messages (for style)
```

**Already-pushed feature branch — don't return "nothing to review."** If the branch
is up-to-date with its upstream, `$UPSTREAM..HEAD` is **empty** even though the branch
carries real work not yet on the base branch. When staged + unstaged + `$RANGE` are all
empty, fall back to reviewing the branch against its **merge-base with the default
branch** (what a PR would show), and say that's the scope you used:

```bash
BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
BASE="${BASE:-main}"
MB=$(git merge-base "origin/$BASE" HEAD 2>/dev/null)
git diff "$MB..HEAD"                        # the branch's whole delta vs base (PR view)
git log "$MB..HEAD" --format='%h %s%n%b'    # its commit messages
```

Only do this when the unpushed scope is empty — it's the "review this pushed branch
before merging" case, not the default. If the user passes an explicit scope (e.g.
"just the staged changes", "only `HEAD`", "compare against `main`"), honor it instead.

Keep the snapshot **in memory or in the scratchpad/temp dir only** — never write it
into the repo tree.

---

## 2. Diff hygiene (before sharing anything with AI)

Real diffs contain noise that wastes review budget, blows up context, and causes
false secret hits. Before analysis, classify each changed file and treat it
accordingly:

**Exclude from AI review by default** (list them, don't analyze their contents):
- **Lockfiles / dependency manifests' generated halves** — `package-lock.json`,
  `yarn.lock`, `pnpm-lock.yaml`, `Cargo.lock`, `poetry.lock`, `go.sum`,
  `Gemfile.lock`, `composer.lock`. (Their *human* side — `package.json`,
  `pyproject.toml`, etc. — IS reviewed, by the dependencies dimension.)
- **Binary / media** — images, fonts, archives, compiled artifacts, `*.min.js`,
  `*.min.css`, source maps. `git diff --numstat` shows `-` for binary files.
- **Vendored / generated** — `vendor/`, `node_modules/` (should be gitignored
  anyway), `dist/`, `build/`, `*.pb.go`, generated clients, snapshot fixtures.

Note them as "excluded from review (N files: lockfiles, binaries, generated)" so
the user knows they weren't silently ignored — but **still run the secret scan over
everything**, because a secret can hide in any added line, generated or not.

**Cap very large diffs.** If the reviewable (non-excluded) diff is very large
(rule of thumb: > ~1500 changed lines or > ~40 files), don't try to review it all
at once:
1. Rank files by significance (source/logic over config over docs; files touched by
   the most hunks; files the commit messages emphasize).
2. Review the **top-N** in depth and **list the remainder** as "not deeply reviewed
   — large diff; re-run scoped to these if needed."
3. Say clearly in the report that the review was **partial** and why. A partial
   review must never be reported as a clean full PASS.

---

### Default to the changed set, offer the full scan

Whole-repo work is the most expensive thing a skill can do, and most runs are asking
about work in progress. **Default to the snapshot (§1); take `--full` for the whole
tree.** This applies to the repo-maintenance scans as much as the diff gates.

Two obligations come with a narrowed default:

- **Say which scope ran.** A changed-set result that reads like a whole-repo result
  is worse than no result.
- **Say what it could not see.** A changed-set scan misses anything the change made
  dead *elsewhere* — deleting the last caller of a helper in an untouched file leaves
  it orphaned, outside the diff. Offer `--full` when findings suggest that happened.

The exception is a skill whose subject genuinely is the whole thing: `/deps-upgrade`
surveys the entire manifest because "what is outdated" scoped to touched packages is
a misleading answer, and the manifest is one small file. Narrowing it would also
duplicate `/review-dependencies`.

## 3. Secret handling (applies before any AI sharing)

The secret scan is always the **first gate**. The diff is not handed to any
subagent until it clears. A dedicated scanner (`gitleaks` / `trufflehog` /
`detect-secrets` — any one) is **required**: if none is installed the secrets
dimension BLOCKs with install instructions and the review does not proceed (there
is no heuristic-only fallback gate). See `skills/review-secrets/SKILL.md` for the
full procedure. Universal rules:

- **A scanner is mandatory** — a missing scanner is a BLOCK, never a silent skip or
  a model-only pass.
- **Run the scanner as ONE bare command, never chained.** A sandboxed or
  non-interactive runner approval-gates each part of a compound command (`&&`, `|`,
  `;`, `$(…)`) separately and may **deny** it — which reads as "the scanner failed"
  when it never ran. Invoke it plain (`gitleaks git --log-opts="…" --redact -v`); read
  `$?` on the next line if you need the exit code.
- **"No scanner" ≠ "scanner blocked by the sandbox."** Only a genuinely missing
  scanner (confirm with `command -v`) or a real hit is a **BLOCK**. A scanner that
  exists but was **permission-denied** is an operator/environment fix, not a code
  BLOCK — say so, don't report the change as failing a scan, and unblock by running
  the bare command or allow-listing `Bash(<scanner>:*)` in `.claude/settings.json`.
- **Never echo a raw secret** — always mask (`AKIA****************`).
- **Newly-added vs. pre-existing**: focus on secrets **added by this change**
  (`+` lines). A secret already committed upstream is still worth flagging, but the
  gate's job is to stop *this push* from introducing one.

---

## 4. Findings format (every dimension, every agent)

- Confidence-rate each finding 0–100; **report only ≥ 80**. Precision over recall —
  a noisy reviewer gets muted.
- Each finding: **Severity** (`BLOCKER` / `WARNING` / `NIT`), **Location**
  (`file:line`, or commit hash for message issues), **What** (one sentence),
  **Why it matters / failure scenario**, **Fix** (concrete).
- Each dimension returns one **verdict**: `PASS`, `WARN`, `BLOCK`, or `SKIP`
  (SKIP = the dimension couldn't run, e.g. no test command; never a false PASS).

**Aggregate verdict** (umbrella):
- `BLOCK` if a secret is found, any dimension `BLOCK`s, or a required command fails.
- `WARN` if only `WARNING`/`NIT` findings.
- `PASS` if all clean.
- If any dimension was `SKIP` or the review was **partial** (§2), say so explicitly
  alongside the verdict — PASS-with-gaps is not the same as PASS.

---

## 5. Interactive vs. non-interactive (CI) mode

The suite runs in two modes. Detect non-interactive mode from an explicit signal:
env var `NJ_AGENTS_CI=1`, a `--ci` argument, or the user stating it's for a
pipeline/hook.

**Interactive (default):** may ask the user to confirm a suspected false positive,
offer to wire a hook, etc. Human in the loop.

**Non-interactive / CI:** never prompt. Any ambiguity resolves to the **safe**
outcome (a suspected secret BLOCKs; it does not wait for confirmation). Emit a
machine-readable summary and honor the exit-code contract below.

### Exit-code contract (for hooks / CI)
When wired into a git hook or pipeline, the runner must map the aggregate verdict to
an exit code:
- `0` — PASS or WARN (push/pipeline may proceed).
- non-zero (`1`) — BLOCK (push/pipeline should stop).

A hook or CI step keys off this code. The suite itself still **advises only** — it
never runs `git push`, and never bypasses a hook with `--no-verify`.

---

## 6. Report artifact / audit trail

Every umbrella run (and optionally each standalone dimension) writes a record of
what was reviewed and the outcome — **never into the repo tree**:

- **Location:** `${NJ_AGENTS_REPORT_DIR:-<repo>/.nj-agents-reports}/`, or the
  scratchpad/temp dir if the repo dir must stay pristine. If writing under the repo,
  ensure the path is gitignored (the umbrella offers to add
  `.nj-agents-reports/` to `.gitignore` — propose, don't silently add).
- **Filename:** `review-<UTC-timestamp>-<short-sha-or-dirty>.md`.
- **Contents:** timestamp, repo + branch, the exact scope reviewed, which secret
  scanner ran (tool name + version), files
  excluded per §2, whether the review was partial, per-dimension verdict + findings,
  and the aggregate verdict + exit code.

The report is a record, not a secret store — it must contain **no unmasked
credentials** (findings reference masked values only).

---

## 7. Safety rails (non-negotiable, every skill and agent)

- **Secret-scan before any AI sharing.** The diff never enters a subagent prompt
  until the scan clears.
- **Never fabricate credentials**, never read or modify the app's auth, never send
  the diff anywhere external (no external API — the current session does the work).
- **Never modify code** to make a check pass; **never install tooling** implicitly
  (missing tools are reported, not installed).
- **Leave no files in the repo tree** except artifacts the user explicitly opted
  into (report dir, hook) — and those are proposed, never silently written.
- **Never run `git push` / `git commit` / `--no-verify`.** The suite reads and
  reports; the human (or the hook's exit code) decides.
- **Propose, don't silently add** any durable repo change — hook install, gitignore
  entry, a documented command note.

---

## 8. Cost control (every skill that spawns agents)

**Moved.** Cost control is not review-specific — a skill spawning six agents costs
the same whatever class it belongs to — so the rules now live in
`CONVENTIONS-orchestration.md §C`, which every class can cite. That file also holds
`§R` (progress reporting), the other half of behaving well while spawning.

This heading stays so existing `§8` citations resolve. Read `§C` for the rules:
state the cost shape before spawning, scale the fleet to the work, skip what has
nothing to do, cap fix rounds at 2, halt on any signal to stop, cheap path first.

---

## Also applies

`CONVENTIONS-orchestration.md` **§U** binds every skill regardless of class —
ground everything in the repo, never run git on your own initiative, no secrets in
output, keep `CHANGELOG.md` current when the change is user-facing, degrade rather
than fail, and say what you did not do. The rules below are what this class adds
on top.
