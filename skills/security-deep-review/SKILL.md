---
name: security-deep-review
description: Use this skill when the user asks to "run a deep security review", "enterprise security audit", "multi-agent security review", "escalate the security review", or wants adversarially-verified, multi-lens security coverage beyond /review-secrets' single pass. Runs the same mandatory secret-scanner gate first, then a Workflow-tool pipeline — parallel specialist finders sweep independent lenses (injection/authz, SSRF/deserialization/path-traversal, supply-chain, crypto/authn, cloud/infra), each finding is adversarially re-checked by independent verifiers (majority-refute kills it), then one synthesis pass produces a severity-ranked BLOCK/WARN/PASS report. Diff-scoped by default; --full sweeps the whole repo. Deliberately invoked, not part of the default pre-push fleet. Works in any git repo; nothing here is project-specific.
version: 0.1.0
class: review
subclass: gate
author: navjyotnishant
---

# Security Deep Review (multi-agent, enterprise depth)

The **escalation** over `/review-secrets`: same mandatory secret-scanner gate first,
then a `Workflow`-tool pipeline — parallel specialist finders sweeping independent
security lenses, each surviving finding adversarially re-checked by independent
verifiers, then one synthesis pass. `/review-secrets` stays the right default for the
pre-push umbrella (cheap, one semantic pass); this skill is the deliberately-invoked,
costlier sibling — the same relationship `/deps-upgrade` has to `/review-dependencies`.
Follow the shared rules in `CONVENTIONS.md` (snapshot scope §1, diff hygiene §2,
secret handling §3, findings format §4, CI mode §5, report §6, safety §7).

> **Finding the conventions file.** It lives at the toolkit repo root, two levels
> above this skill — not beside `SKILL.md`. Skills are usually installed as
> symlinks into your runner's skills directory, so a plain relative path resolves against the
> *link* and misses it. Resolve the link first:
>
> ```bash
> ROOT="$(dirname "$(readlink -f "<this skill's base directory>")")/.."
> ```
>
> then read `$ROOT/CONVENTIONS.md`. If a file is genuinely absent, say so and continue
> with the procedure below rather than stopping.

> **Every skill follows `CONVENTIONS-orchestration.md` §U** — ground everything in
> the actual repo, never run git on your own initiative, no secrets in output,
> keep `CHANGELOG.md` current when the change is user-facing, degrade rather than
> fail, and say what you did not do.

> **Spawning subagents — `CONVENTIONS-orchestration.md`.** This skill spawns agents
> — the Workflow pipeline spawns 5 lens finders in parallel, then up to 3 adversarial
> verifiers per surviving candidate finding — so `§C` (cost) and `§R` (progress
> reporting) apply, with a larger cost shape than `/review-secrets`' 1–2 calls.
> **Cost shape:** typically 5 finder calls + up to 15 verifier calls (commonly
> 15–30 total agent calls for a mid-size diff). State it and get a yes before the
> first dispatch (skip the prompt only in CI mode); halt on any signal to stop; never
> chain into another agent-spawning skill unprompted. Announce the **roster** before
> dispatch and narrate each Workflow phase as it starts (find, then verify, then
> synthesize) — `§R`.

## Dependencies

Detected at runtime, never installed by this skill (`§A5`).

| Tool | Used for | Without it |
|---|---|---|
| `gitleaks` *or* `trufflehog` *or* `detect-secrets` | the mandatory secret gate, run first, identical to `/review-secrets` | **BLOCK** with install instructions — the gate cannot be skipped |

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  SECURITY DEEP REVIEW — MULTI-AGENT, ENTERPRISE DEPTH              ║
╠══════════════════════════════════════════════════════════════════╣
║  Escalation over /review-secrets: same mandatory secret-scanner   ║
║  gate first (BLOCKs if none installed / on any hit) — then a      ║
║  multi-lens PARALLEL finder sweep, each finding adversarially     ║
║  re-checked by independent verifiers before it survives.          ║
║                                                                    ║
║  Scope defaults to your changed set (staged+unstaged+unpushed).   ║
║  Pass --full to sweep the whole repo instead.                     ║
║                                                                    ║
║  No external API. This session + its subagents only. ADVISES      ║
║  only — never fixes, pushes, or commits.                          ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **A diff to review** (staged + unstaged + unpushed), or `--full` for the whole
  tree; if diff-scoped and empty, report PASS and stop (Step 1).
- **No external API key** — uses the current AI session.
- **REQUIRED:** a dedicated secret scanner on PATH — `gitleaks`, `trufflehog`, or
  `detect-secrets` (any one). If none is installed, this BLOCKs with install
  instructions (Step 2); there is no heuristic-only fallback gate.

## Step 1 — Resolve scope: diff-default, `--full` opt-in

Default to the **changed set** (`CONVENTIONS.md §1` snapshot — staged + unstaged +
unpushed). Take `--full` for the whole tree, same pattern as `/dead-code-finder`
(`CONVENTIONS.md §2`): whole-repo work is the most expensive thing a skill can do,
and most runs are asking about work in progress.

**A changed-set result is not a clean bill of health.** Say so, not imply otherwise:

- A pre-existing vulnerability in a file the diff never touched.
- A security-relevant contract change (e.g. an authz assumption) in a file the diff
  didn't touch but that calls into changed code.

If the changed set is **empty** and `--full` was not requested, there is nothing to
review — report **PASS** and stop **before** spawning anything (`§U`). Do not
silently fall through to `--full`.

**State the scope used** in the report; don't silently pick one.

## Step 2 — Hard secret gate (identical to `/review-secrets`, not reimplemented)

Run `skills/review-secrets/SKILL.md`'s Steps 1–4 verbatim over the resolved scope:
detect a scanner (`gitleaks`/`trufflehog`/`detect-secrets`) → **BLOCK** with install
instructions if none is on PATH → **BLOCK** and mask on any hit, sharing nothing →
clean scan proceeds. Do not reimplement this gate here; cite the file so the two
procedures never drift independently. Nothing in Step 3 onward runs until this
clears.

## Step 3 — Cost-shape statement + roster announcement (before any dispatch)

State the cost shape (above) in one line and get a yes in interactive mode (skip the
prompt only in CI). Print the roster:

```
Scope: diff (or --full), N files, M reviewable lines
Plan:  Find phase — 5 lens finders in parallel:
         ⋯ security-finder[injection-authz]   SQLi/cmd-injection/authz gaps/IDOR
         ⋯ security-finder[ssrf-deser-path]    SSRF/unsafe deserialization/path traversal
         ⋯ security-finder[supply-chain]       dependency/manifest risk signals
         ⋯ security-finder[crypto-authn]       weak crypto/authn/token handling
         ⋯ security-finder[cloud-infra]        cloud/infra misconfig (if applicable)
       Verify phase — up to 3 security-verifier agents per surviving candidate,
         pipelined to start as soon as a finder returns (no barrier wait)
       Synthesis — 1 aggregation pass
       (secrets/credentials are NOT a lens here — Step 2's gate + /review-secrets'
       own semantic pass already own that ground; duplicating it would be
       redundant spend, not extra rigor)
Proceed? [Y/n]
```

**Scale the fleet to the work** (`§C`): a lens with nothing applicable in this repo
(e.g. `cloud-infra` when there's no IaC/config touched) SKIPs and says so rather than
spawning a finder with nothing to find.

## Step 4 — Run the Workflow pipeline

See [`docs/architecture/pipeline-security-deep-review.png`](../../docs/architecture/pipeline-security-deep-review.png)
for the Find → Verify → Synthesize shape at a glance.

Hand this script to the `Workflow` tool. `LENSES` and `snapshot` are filled from
Steps 1–3; `N_VERIFIERS` is fixed at 3.

```js
export const meta = {
  name: 'security-deep-review',
  description: 'Multi-lens parallel security find, adversarial verify, synthesize',
  phases: [
    { title: 'Find', detail: 'lens finders in parallel' },
    { title: 'Verify', detail: 'up to 3 adversarial verifiers per candidate' },
    { title: 'Synthesize', detail: 'one aggregation pass' },
  ],
}

// Inlined from agents/security-finder.md and agents/security-verifier.md's core
// instructions — NOT passed via opts.agentType. The Workflow tool's agent
// registry is populated from the harness's own agent list, which a newly
// authored agents/*.md file is not guaranteed to be in yet even after
// ./install.sh; opts.agentType: 'security-finder' throws "agent type not
// found" until that registry catches up. Inline prompts always work.
const FINDER_PERSONA = `You are an application security reviewer working one lens at a time. You are given a single lens brief and a diff snapshot — search only within that lens; other parallel calls cover every other lens. Do not report secrets/leaked credentials (that is a separate mandatory gate, already run and clean). Rate each finding 0-100 confidence; report ONLY findings >= 80. Prefer precision over coverage. Anchor every finding to file:line and construct a concrete attack scenario (input/actor -> impact). Assign each finding a stable id. If nothing in this lens clears the bar, or the lens plainly does not apply to this diff, return an empty findings array with a skip_reason. Read-only: never modify files, never run git push/commit.`

const VERIFIER_PERSONA = `You are an independent adversarial security verifier. You are given ONE candidate finding and your job is to try to REFUTE it, not confirm it. Re-read the exact file:line cited directly in the repo rather than trusting the finder's paraphrase. Check: is the input actually reachable/untrusted, does an existing check elsewhere neutralize it, do the line numbers still match, is the attack scenario actually exploitable. Return id, verdict (confirm or refute), and one sentence of reasoning describing what you specifically checked. Default to skepticism, but if you cannot find a concrete reason to refute after genuinely looking, confirm. Read-only; never invent a new finding.`

const LENSES = [
  { id: 'injection-authz', brief: 'SQL/command/template injection, missing authz/authn, IDOR' },
  { id: 'ssrf-deser-path', brief: 'SSRF, unsafe deserialization/eval, path traversal, zip-slip' },
  { id: 'supply-chain',    brief: 'dependency/manifest risk signals: typosquatting, unpinned ranges, known-bad versions' },
  { id: 'crypto-authn',    brief: 'weak/absent crypto, hardcoded keys/IVs, weak token generation, disabled TLS verification' },
  { id: 'cloud-infra',     brief: 'cloud/infra misconfig in IaC or config files touched by the diff' },
]
const N_VERIFIERS = 3

phase('Find')
const findResults = (await parallel(LENSES.map(lens => () =>
  agent(
    `${FINDER_PERSONA}\n\nLens: "${lens.id}"\nLens brief: ${lens.brief}\n\n${scopeText}\n\nRun \`git diff\`/\`git diff --cached\` yourself (or read untracked new files directly) to see the actual content, scoped to this lens only.`,
    { label: `find:${lens.id}`, phase: 'Find', schema: FINDINGS_SCHEMA }
  )
))).filter(Boolean)

const allFindings = findResults.flatMap(r => r.findings.map(f => ({ ...f, lens: r.lens })))
let surviving = []
if (allFindings.length > 0) {
  const verified = await pipeline(
    allFindings,
    finding => parallel(Array.from({ length: N_VERIFIERS }, (_, i) => () =>
      agent(
        `${VERIFIER_PERSONA}\n\nFinding id: ${finding.id}\nLens: ${finding.lens}\nSeverity: ${finding.severity}\nLocation: ${finding.location}\nSummary: ${finding.summary}\nAttack scenario: ${finding.attack_scenario || 'n/a'}\nClaimed confidence: ${finding.confidence}`,
        { label: `verify:${finding.id}:${i}`, phase: 'Verify', schema: VERDICT_SCHEMA }
      )
    )),
    (votes, finding) => {
      const v = votes.filter(Boolean)
      const confirms = v.filter(x => x.verdict === 'confirm').length
      const refutes = v.filter(x => x.verdict === 'refute').length
      return { finding, votes: v, survives: confirms >= refutes }
    }
  )
  surviving = verified.filter(v => v.survives)
}

phase('Synthesize')
const report = await agent(buildSynthesisPrompt(surviving, findResults, scopeMeta), { schema: REPORT_SCHEMA })
return report
```

Every Find-phase call **spawns the `security-finder` agent's persona**, and every
Verify-phase call **spawns the `security-verifier` agent's persona** — inlined as
`FINDER_PERSONA`/`VERIFIER_PERSONA` text above (sourced verbatim from
`agents/security-finder.md`/`agents/security-verifier.md`'s core instructions)
concatenated with the per-call lens brief or finding-under-test, **not**
`opts.agentType`. The Workflow tool's agent-type registry is populated from the
harness's own list and is not guaranteed to include a just-authored `agents/*.md`
file yet, even right after `./install.sh`; `opts.agentType: 'security-finder'`
throws `agent type 'security-finder' not found` until that registry catches up.
Inline prompts have no such dependency and always work — spawn both agents this way,
and keep the `agents/*.md` files as the source of truth for what gets inlined, not
as a registry reference. This is a **timing** issue, not a permanent property of
these two agents — `opts.agentType` may well resolve for `security-finder`/
`security-verifier` today, now that they've been installed for a while (see
`/pre-push-review`'s migration, where `opts.agentType` was tried and confirmed
live for five agents established since July/August 2026). Re-verify before
switching this skill over, rather than assuming either direction.

`buildSynthesisPrompt` must handle the **zero-findings case explicitly** — when
`surviving.length === 0`, do not hand the synthesis agent a vague "summarize"
instruction with no data; an under-specified prompt over empty input drifts into
hallucinating unrelated content (observed once: it fabricated a generic
correctness/tests/style report unconnected to this skill's actual lenses). Instead
state directly: no findings survived (or none were found), list each lens with its
candidate count and `skip_reason`, and require the report to say PASS plus the
scope caveat — nothing else.

Find→Verify is a `pipeline()`, not a barrier — verification of an early finding
starts while later finders may still be running. Synthesis runs once, after Verify
fully drains — a real barrier is correct there, since the report needs the whole
surviving set together.

## Step 5 — Adversarial verify

Each candidate finding (already ≥80 confidence from its own finder, per
`CONVENTIONS.md §4`) is spawned to `security-verifier` **N=3 times**, each verifier
blind to the others' votes and explicitly prompted to try to **refute** the finding,
not confirm it — reachability of the claimed input, whether an existing check
elsewhere neutralizes it, whether the cited lines still match the snapshot.

- **Majority-refute** (2+ of 3 vote refute) → the finding is dropped silently
  (logged for the report's "considered and cleared" note, not surfaced as noise).
- **Majority-confirm or a tie** → resolve toward caution (survives to Step 6), same
  ambiguity-resolves-conservatively rule as CI mode (`§5`).

## Step 6 — Synthesize and report

One synthesis agent takes every surviving finding, groups by severity, assigns
confidence + `file:line` + a per-finding verdict per `CONVENTIONS.md §4`, and
produces the **aggregate dimension verdict**:

- **BLOCK** — any surviving finding is exploitable, or the secret gate failed.
- **WARN** — only hardening nits survived.
- **PASS** — nothing survived verification (say how many candidates were considered
  and cleared, not just "clean").

State the Step 1 scope-limitation caveat in the report. Write the report artifact
per `CONVENTIONS.md §6` (masked values, outside the repo tree).

## Step 7 — CI mode

Per `CONVENTIONS.md §5` / `NJ_AGENTS_CI`: no prompts, ambiguity resolves toward
**BLOCK**, exit-code contract (0 PASS/WARN, 1 BLOCK, 2 no-verdict). The Step 3
roster confirmation is skipped in CI — state the fleet and proceed.

## Step 8 — Cleanup

Advise-only — never fixes, pushes, or commits. Remove scratch files. Say what wasn't
covered: any lens that SKIPped for having nothing applicable, and — if diff-scoped —
the Step 1 caveat about what a diff-only pass cannot see.

## Report format

```
## Security Deep Review

Scope:     diff (N files) | full repo
Gate:      <scanner> clean | BLOCK — <reason>
Fleet:     5 finders, <k> candidates found, <v> verified, <s> survived
Verdict:   BLOCK | WARN | PASS
Findings:  <severity-ranked list — file:line, confidence, one-line summary>
Not seen:  <scope caveat from Step 1, or "none — full repo scanned">
Report:    <path to artifact>
```

## Safety rails

- **Secret gate is mandatory and unreimplemented** — always defers to
  `/review-secrets`' Steps 1–4 (§P equivalent: never duplicate the gate's logic).
- **Cost stated + confirmed before dispatch** (§C); scale the fleet to the work,
  never spawn a finder for a lens with nothing to find.
- **Adversarial verify before any finding is reported** — a finder's own confidence
  is never the final word.
- **Advise only** — never fixes, pushes, or commits (§U). No secrets in output;
  values stay masked.
- **State the scope used and what it could not see** (Step 1) — a diff-scoped PASS
  is not a whole-repo clean bill of health.
