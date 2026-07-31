---
name: review-secrets
description: Use this skill when the user asks to "scan my changes for secrets", "check the diff for leaked keys/credentials", "run the security review on this change", or wants a security-focused review of the current commit or uncommitted work before pushing. REQUIRES a dedicated secret scanner (gitleaks/trufflehog/detect-secrets) on PATH — runs it over the diff first as a HARD GATE (BLOCKs with install instructions if none is installed) — then a deeper semantic security pass. Works in any git repo; nothing here is project-specific.
version: 0.4.0
class: review
subclass: gate
author: navjyotnishant
---

# Review: Secrets & Security

Security-focused review of the **current commit or uncommitted changes**, in two
layers:

1. **Secret gate** — detect leaked credentials in the diff with a **required**
   dedicated scanner (`gitleaks` / `trufflehog` / `detect-secrets` — any one). This
   is a **hard gate**: nothing is shared with any subagent until it clears, and if
   no scanner is installed the dimension BLOCKs with install instructions (no
   heuristic-only fallback).
2. **Semantic security pass** — via the `secrets-reviewer` agent, once the diff is
   cleared: injection, authz gaps, unsafe patterns.

This is the dimension the umbrella `pre-push-review` runs **first**. Follow the
shared rules in `CONVENTIONS.md` (snapshot scope §1, diff hygiene §2, secret
handling §3, CI mode §5, report §6, safety §7).

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

> **Spawning subagents — `CONVENTIONS-orchestration.md`.** This skill spawns agents,
> so `§C` (cost) and `§R` (progress reporting) apply. **Cost shape:** 1–2 agent calls.
> State it and get a yes before the first dispatch; cap fix rounds at 2; halt on any
> signal to stop. Announce the **pipeline** up front and each stage as it starts, so a stall is
> attributable to a named stage (`§R`).


## Dependencies

Detected at runtime, never installed by this skill (`§A5`).

| Tool | Used for | Without it |
|---|---|---|
| `gitleaks` *or* `trufflehog` *or* `detect-secrets` | scanning the diff before anything is shared with an agent | **BLOCK** with install instructions — there is no heuristic fallback |

## Step 0 — Print the warning banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  SECRETS & SECURITY REVIEW                                        ║
╠══════════════════════════════════════════════════════════════════╣
║  A dedicated secret scanner (gitleaks / trufflehog /              ║
║  detect-secrets) runs over your diff BEFORE anything is shared     ║
║  with AI. One of these is REQUIRED — if none is installed, this    ║
║  BLOCKs with install instructions. If a credential/key/token is    ║
║  detected, this STOPS and shares nothing until you remove it.      ║
║                                                                   ║
║  Only after the scan clears is the diff shared with AI (this      ║
║  session + subagent) for a deeper security pass. No external      ║
║  API is called. Nothing leaves this machine. ADVISES only.        ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **A diff to review** (staged + unstaged + unpushed); if empty, report and stop.
- **No external API key** — uses the current AI session.
- **REQUIRED:** a dedicated secret scanner on PATH — `gitleaks`, `trufflehog`, or
  `detect-secrets` (any one). If none is installed, this dimension BLOCKs with
  install instructions (Step 3); there is no heuristic-only fallback gate.

## Step 1 — Build the snapshot (local, NOT yet shared)

Assemble the snapshot per `CONVENTIONS.md §1`. Apply diff hygiene per §2 — but
note: the secret scan runs over **all** added lines, including generated/lockfile/
excluded-from-review files, because a secret can hide anywhere. (Hygiene exclusions
apply to the *semantic* review in Step 4, not to the secret scan in Steps 2–3.)

## Step 2 — Detect a dedicated scanner (all three supported equally)

The suite supports the three industry-standard secret scanners as first-class
equals. Detect which, if any, are on PATH:

```bash
command -v gitleaks
command -v trufflehog
command -v detect-secrets
```

If **more than one** is present, prefer them in this order — `gitleaks`, then
`trufflehog`, then `detect-secrets` (order is a tie-break only; any of the three is
authoritative). If **exactly one** is present, use it. Run it over the changes and
treat its output as authoritative:

- **gitleaks** (Go binary, MIT): `gitleaks protect --staged --redact -v` for staged,
  and `gitleaks detect --no-git --redact` over the working tree / a written-out
  patch of the unpushed range. `--redact` masks values in output.
- **trufflehog** (Go binary, Apache-2.0):
  `trufflehog git file://. --since-commit <range-base> --only-verified` — prefer
  verified findings to cut noise; still surface unverified as WARN.
- **detect-secrets** (Python, Apache-2.0): `detect-secrets scan` over the changed
  files, diffed against the repo's `.secrets.baseline` if one exists.

Record the tool name and version for the report (`CONVENTIONS.md §6`).

If a scanner **is** present, run it (Step 2 above) and go to Step 4.

## Step 3 — No scanner installed → BLOCK (a scanner is mandatory)

A dedicated scanner is **required** — the secret gate does not run on model
heuristics alone. If **none** of the three is on PATH, the secrets dimension
returns **BLOCK** and the review does **not** proceed (no agent is spawned, nothing
is shared). Print the install instructions and stop:

```
BLOCK — no secret scanner installed.

This review requires one of these industry-standard, free/open-source secret
scanners on your PATH. Install any ONE, then re-run:

  • gitleaks (MIT)            — recommended, fast Go binary
      macOS:   brew install gitleaks
      Linux:   see https://github.com/gitleaks/gitleaks#installing
      Go:      go install github.com/gitleaks/gitleaks/v8@latest
      Docker:  docker run -v "$PWD:/repo" zricethezav/gitleaks:latest detect -s /repo

  • trufflehog (Apache-2.0)   — verified-secret detection
      macOS:   brew install trufflehog
      Linux:   curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh
      Go:      go install github.com/trufflesecurity/trufflehog/v3@latest

  • detect-secrets (Apache-2.0, Yelp) — Python, baseline-friendly
      pipx:    pipx install detect-secrets
      pip:     pip install detect-secrets

Verify with: gitleaks version  (or trufflehog --version / detect-secrets --version)
```

Do **not** install anything yourself — only the user installs tooling
(`CONVENTIONS.md §7`). In CI/non-interactive mode this is a hard failure: BLOCK,
exit code 1. The umbrella treats a missing scanner as an overall **BLOCK** — a
push must not proceed without an authoritative secret scan.

## Step 4 — Gate decision

- **Any scanner hit → HARD STOP.** Print `file:line`, the rule/pattern class, and
  the value **masked**. Do **not** spawn the agent, do **not** share the diff. In
  interactive mode, tell the user to remove/rotate it (or add a scanner-native
  allowlist entry for a confirmed false positive) and re-run. In CI mode
  (`CONVENTIONS.md §5`), do not prompt — BLOCK with exit code 1.
- **Clean → proceed to Step 5.**

The Step 5 semantic pass additionally reasons over added lines for token shapes the
scanner might not key on (AWS `AKIA…`, GitHub `ghp_…`, private-key headers, JWTs,
DB URLs with inline credentials, high-entropy assignments), as a **supplement** to —
never a replacement for — the mandatory scanner gate.

## Step 5 — Deeper semantic security pass

**Cost check first (`CONVENTIONS.md §8`).** The scanner gate above is the mandatory
part and has already run; this agent is the optional depth on top of it. Skip it
when the diff cannot plausibly contain the classes it looks for — a docs-only or
config-comment change has no endpoints, queries, or deserialization — and report
`SKIP — no code paths in this diff` rather than spawning. Otherwise state the scope
in one line and proceed. Never re-run more than twice on the same change without
being asked.

Spawn the `secrets-reviewer` agent with the cleared, hygiene-filtered snapshot. It
reviews for security issues that aren't literal secrets: injection (SQL/command/
template), missing authz on new endpoints/handlers, IDOR, unsafe deserialization,
path traversal, SSRF, weak/absent crypto, disabled TLS verification, permissive
CORS, secrets that should come from a secret store but are structurally hardcoded.

## Step 6 — Report

Per `CONVENTIONS.md §4` and §6: which scanner ran (tool name + version), the gate
result, the agent's findings (≥80 confidence, masked values), and a dimension
verdict — **BLOCK** for any secret, exploitable issue, or a missing scanner; **WARN**
for hardening nits; **PASS** if clean. Write the report artifact (§6). Advises only;
clean up scratch files.
