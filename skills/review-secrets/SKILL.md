---
name: review-secrets
description: Use this skill when the user asks to "scan my changes for secrets", "check the diff for leaked keys/credentials", "run the security review on this change", or wants a security-focused review of the current commit or uncommitted work before pushing. Runs a dedicated secret scanner (gitleaks/trufflehog/detect-secrets) over the diff first as a HARD GATE — falling back to a model-reasoned scan if none is installed — then a deeper semantic security pass. Works in any git repo; nothing here is project-specific.
version: 0.2.0
---

# Review: Secrets & Security

Security-focused review of the **current commit or uncommitted changes**, in two
layers:

1. **Secret gate** — detect leaked credentials in the diff. Prefer a real,
   dedicated scanner; fall back to a model-reasoned scan if none is installed.
   This is a **hard gate**: nothing is shared with any subagent until it clears.
2. **Semantic security pass** — via the `secrets-reviewer` agent, once the diff is
   cleared: injection, authz gaps, unsafe patterns.

This is the dimension the umbrella `pre-push-review` runs **first**. Follow the
shared rules in `CONVENTIONS.md` (snapshot scope §1, diff hygiene §2, secret
handling §3, CI mode §5, report §6, safety §7).

## Step 0 — Print the warning banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  SECRETS & SECURITY REVIEW                                        ║
╠══════════════════════════════════════════════════════════════════╣
║  A secret scan runs over your diff BEFORE anything is shared with ║
║  AI. Preferred: a dedicated scanner (gitleaks / trufflehog /      ║
║  detect-secrets) if installed; otherwise a model-reasoned scan.   ║
║  If a credential/key/token is detected, this STOPS and shares     ║
║  nothing until you remove it.                                     ║
║                                                                   ║
║  Only after the scan clears is the diff shared with AI (this      ║
║  Claude session + subagent) for a deeper security pass. No        ║
║  external API is called. Nothing leaves this machine. ADVISES     ║
║  only.                                                            ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop and say so.
- **A diff to review** (staged + unstaged + unpushed); if empty, report and stop.
- **No external API key** — uses the current Claude session.
- **Recommended (not required):** a dedicated secret scanner on PATH — `gitleaks`,
  `trufflehog`, or `detect-secrets`. Without one, the scan still runs (model
  fallback) but coverage is weaker; the report states which ran.

## Step 1 — Build the snapshot (local, NOT yet shared)

Assemble the snapshot per `CONVENTIONS.md §1`. Apply diff hygiene per §2 — but
note: the secret scan runs over **all** added lines, including generated/lockfile/
excluded-from-review files, because a secret can hide anywhere. (Hygiene exclusions
apply to the *semantic* review in Step 4, not to the secret scan in Steps 2–3.)

## Step 2 — Detect a real scanner, prefer it

Check, in order, for a dedicated scanner on PATH:

```bash
command -v gitleaks       # preferred
command -v trufflehog
command -v detect-secrets
```

If one is found, run it over the changes and treat its output as authoritative:

- **gitleaks:** `gitleaks protect --staged --redact -v` for staged, and
  `gitleaks detect --no-git --redact` over the working tree / a written-out patch of
  the unpushed range. Use `--redact` so values are masked in output.
- **trufflehog:** `trufflehog git file://. --since-commit <range-base> --only-verified`
  (prefer verified findings to cut noise; still surface unverified as WARN).
- **detect-secrets:** `detect-secrets scan` over the changed files, diffed against a
  baseline if the repo has one.

Record the tool name and version for the report (`CONVENTIONS.md §6`).

## Step 3 — Fallback: model-reasoned scan (only if no scanner is installed)

If no dedicated scanner is on PATH, perform the scan by reasoning over the added
lines yourself, and **state in the report that the model fallback was used and that
installing gitleaks is recommended for stronger guarantees.** Look for:

- **Known token shapes** — AWS `AKIA[0-9A-Z]{16}`, GCP `AIza[0-9A-Za-z_\-]{35}`,
  GitHub `ghp_`/`gho_`/`ghs_`, Slack `xox[baprs]-`, Stripe `sk_live_`/`rk_live_`,
  Google OAuth, private-key headers (`-----BEGIN ... PRIVATE KEY-----`), JWTs
  (`eyJ...` three base64 segments), npm/PyPI tokens, Azure connection strings,
  database URLs with inline credentials (`scheme://user:pass@host`).
- **Keyworded assignments** — `password`, `passwd`, `secret`, `api[_-]?key`,
  `token`, `access[_-]?key`, `client[_-]?secret` assigned a non-placeholder value.
- **High-entropy strings** — long random base64/hex assigned to a variable, even
  without a keyword.
- **Exclusions / likely false positives** — obvious placeholders
  (`your-key-here`, `xxxx`, `example`, `changeme`, `<...>`, `REDACTED`), values that
  already exist in a committed `.env.example`, and test fixtures clearly marked as
  fake. Note them, don't hard-stop on them.

## Step 4 — Gate decision

- **Any credible hit (from scanner or fallback) → HARD STOP.** Print `file:line`,
  the pattern class, and the value **masked**. Do **not** spawn the agent, do
  **not** share the diff. In interactive mode, tell the user to remove/rotate it
  (or confirm a false positive) and re-run. In CI mode (`CONVENTIONS.md §5`), do not
  prompt — BLOCK with exit code 1.
- **Clean → proceed to Step 5.**

## Step 5 — Deeper semantic security pass

Spawn the `secrets-reviewer` agent with the cleared, hygiene-filtered snapshot. It
reviews for security issues that aren't literal secrets: injection (SQL/command/
template), missing authz on new endpoints/handlers, IDOR, unsafe deserialization,
path traversal, SSRF, weak/absent crypto, disabled TLS verification, permissive
CORS, secrets that should come from a secret store but are structurally hardcoded.

## Step 6 — Report

Per `CONVENTIONS.md §4` and §6: which scanner ran (name+version or "model
fallback"), the gate result, the agent's findings (≥80 confidence, masked values),
and a dimension verdict — **BLOCK** for any secret or exploitable issue, **WARN**
for hardening nits, **PASS** if clean. Write the report artifact (§6). Advises
only; clean up scratch files.
