# hooks/

Shell hooks that make the toolkit's advice mechanical instead of relying on the
model to remember.

Installed as symlinks by `./install.sh` (into `~/.claude/hooks/`), but **not wired
up** unless you ask — registering a hook edits your `settings.json`, which the
installer never does behind your back.

## `suggest-skills.sh`

A `UserPromptSubmit` hook. Matches the prompt against the skills that ship here and
adds a one-line note naming the ones that fit. It only **adds context** — it never
blocks a prompt and never runs a skill.

Why it exists: `global/AGENTS.md` already says "prefer the matching skill over
improvising the same task by hand," but that relies on the model remembering, and in
a long build/test/PR loop it quietly stops happening.

`check.sh` keeps it honest — the hook hand-lists skills, so `check_hook_sync` flags
any skill it never suggests.

### Wiring it up

```bash
./install.sh --with-hooks      # idempotent; leaves existing hooks alone
```

Or add it to `~/.claude/settings.json` yourself:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/suggest-skills.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

Use the absolute path — `~` is not expanded in that field.

### Requirements

`jq`, for reading the prompt out of the hook payload. It is **detected, not
required**: without `jq` the hook exits 0 silently rather than erroring on every
prompt.

---

## `git/pre-push`

The local stand-in for branch protection, which needs GitHub Pro on a private repo.

Runs exactly what CI runs — `check.sh --strict` then `tests/assert.sh` — and blocks
the push if either fails. Both are LLM-free and take about a second, so it is cheap
enough to fire on every push. It deliberately does **not** run
`bin/nj-agents-review`: that spends real money per push. Run `/pre-push-review` by
hand when you want the deep pass.

```bash
./install.sh --git-hooks
```

Three things it is not:

- **Not committed.** `.git/hooks` is not tracked by git, so it is per-clone and
  per-machine — that is why the source lives here and gets copied in. A fresh clone
  has no hook until you run the installer.
- **Not unbypassable.** `git push --no-verify` skips it, deliberately: a visible,
  conscious override rather than a wall.
- **Not server-side.** Pushes from another clone or the web UI are not gated. Real
  branch protection is still the answer; this covers the realistic case.

The installer never overwrites a hook that differs from the source — it reports and
leaves it alone.

---

## `git/pre-push-review` — the LLM review gate (per project, opt-in)

Runs `/pre-push-review` and blocks the push when the verdict is BLOCK — but **only
when the push targets a protected branch**: `main`, `master`, `PRD`, or `release/*`.
Feature branches push free and silent.

```bash
./install.sh --review-gate --project /path/to/your/repo
```

### Why it is not part of `git/pre-push`

That hook fires on every push and is deliberately LLM-free. This one spends **~5
agents per run**, and three files in this repo already record the judgement that
per-push LLM spend is unacceptable. Gating on the target ref is what makes it
affordable: the inner loop stays free, and the branch that reaches production does
not.

### Why not a merge hook

`pre-merge-commit` looks like the right hook and is not — git does not run it for a
**fast-forward** merge. Measured against one real project's history, 6 of 8 merges
to `main` were fast-forwards, so a merge hook would have silently passed on the
majority. A gate that looks installed and does nothing is worse than no gate.

### Controls

| | |
|---|---|
| `NJ_REVIEW_SKIP=1` | Bypass — but it says so on the way past. |
| `NJ_REVIEW_AUTO=1` | No confirmation prompt. For CI and unattended workflows. |
| `NJ_REVIEW_REFS` | Override the protected list, space-separated short names. |
| `git push --no-verify` | Git's own escape hatch, as with any hook. |

Without a terminal (a workflow, a CI runner, an editor's git integration) it
auto-proceeds rather than hanging on a prompt nobody can answer.

### Degrades rather than blocks

A missing `nj-agents-review` on PATH, or a harness error from it, **warns and lets
the push through**. Only a real BLOCK verdict stops one. Blocking every push to
`main` over a setup gap would get the hook deleted within a day, and a tooling
failure is not a code finding.

It says so every time, though — a gate that goes quiet is indistinguishable from one
that was uninstalled.

### The pre-push slot is shared

Git only runs a hook named `pre-push`, so this cannot coexist with another one by
itself. If the slot is taken, the installer **leaves your hook alone**, drops the
source at `.git/hooks/pre-push-review`, and prints the line to chain it:

```sh
"$(git rev-parse --git-dir)"/hooks/pre-push-review "$@" || exit 1
```

---

## `git/pre-push-e2e` — the E2E gate (per project)

Refuses a push whose test suite is red. Unlike `pre-push` above, which validates
*this* repo, this one is portable: install it into any project.

```bash
./install.sh --git-hooks --project /path/to/your/repo
mkdir -p /path/to/your/repo/.nj-agents
echo 'NJ_E2E_BASE_URL=http://localhost:3000' > /path/to/your/repo/.nj-agents/e2e.conf
```

Until `.nj-agents/e2e.conf` exists it exits 0 on every push **and says it is not
configured**. That is deliberate: a gate that goes quiet is indistinguishable from
one that was uninstalled.

**It spends nothing.** It runs the repo's own test command and honours the exit
code — no agent, no API call. `.github/workflows/check.yml` and `git/pre-push` both
already record the judgement that per-push LLM spend is unacceptable, and
`/e2e-suite` costs 1 + n agents (one per failure), so it is a worse fit for a push
hook than the review those files exclude.

What it does, in order — each step exits with a reason rather than silently:

1. **Opt-in** — no `e2e.conf` and no `NJ_E2E_BASE_URL` → skip
2. **Detect the runner** — documented command → `package.json` script → E2E config
   → pytest/`verify_*.py`. Deliberately *not* a bare `test` script: that is usually
   the unit suite, and running it here would make the gate silently duplicate what
   already runs on commit while reporting itself as an E2E gate
3. **Resolves to specs?** — a detected runner matching zero specs is a SKIP, never a
   pass. This is GitHub #9: a config left behind after its specs were deleted
   detects cleanly and matches nothing
4. **Run it** — non-zero blocks the push

`E2E_CMD` in `e2e.conf` overrides detection entirely.

### The paid pass belongs in CI

`/e2e-suite` triage — classify each failure, weigh it against flake history, produce
a report — costs real money and belongs once per PR, not once per push:

```yaml
# .github/workflows/e2e.yml
on: pull_request
jobs:
  e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bin/nj-agents-e2e --base-url "${{ secrets.STAGING_URL }}"
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

`bin/nj-agents-e2e` maps the verdict to an exit code (0 PASS/WARN/SKIP, 1 BLOCK,
2 harness error), which `claude -p` alone does not — it exits 0 whatever the verdict.
