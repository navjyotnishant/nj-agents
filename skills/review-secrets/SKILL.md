---
name: review-secrets
description: Use this skill when the user asks to "scan my changes for secrets", "check the diff for leaked keys/credentials", "run the security review on this change", or wants a security-focused review of the current commit or uncommitted work before pushing. Runs a LOCAL secret scan over the diff first (as a hard gate), then a deeper semantic security pass. Works in any git repo; nothing here is project-specific.
version: 0.1.0
---

# Review: Secrets & Security

Security-focused review of the **current commit or uncommitted changes**. Runs
in two layers: (1) a **local** scan for leaked credentials — this is a hard gate
that must clear before any diff is shared with AI — then (2) a deeper semantic
pass (injection, authz, unsafe patterns) via the `secrets-reviewer` agent.

This is the dimension the umbrella `pre-push-review` runs **first**, before any
other reviewer sees the diff.

## Step 0 — Print the warning banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  SECRETS & SECURITY REVIEW — AI-ASSISTED                         ║
╠══════════════════════════════════════════════════════════════════╣
║  A LOCAL secret scan runs over your diff BEFORE anything is       ║
║  shared with AI. If a credential/key/token is detected, this      ║
║  STOPS and shares nothing until you remove it.                    ║
║                                                                   ║
║  Only after the local scan clears is the diff shared with AI      ║
║  (this Claude session + subagent) for a deeper security pass.     ║
║  No external API is called. This tool ADVISES only.               ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A git repository** (`git rev-parse --git-dir`); else stop.
- **A diff to review** (staged + unstaged + unpushed); if empty, report and exit.
- **No external API key** — uses the current Claude session.

## Step 1 — Build the snapshot (local, NOT yet shared)

Same scope as the umbrella: `git diff --cached` + `git diff` + the unpushed
range (`@{upstream}..HEAD`, falling back to the default branch, then `HEAD`).
Focus the scan on **added lines** (`+` lines in the unified diff) — that's what
this change introduces. Keep it in memory / scratchpad only; never write to the
repo.

## Step 2 — Local secret scan (the hard gate)

Scan the added lines for likely secrets — do this **locally**, without sharing
the diff with any subagent:

- **Pattern shapes** (non-exhaustive; extend per ecosystem): cloud keys
  (`AKIA[0-9A-Z]{16}`, GCP `AIza...`, Azure connection strings), generic
  `api[_-]?key`, `secret`, `token`, `password`, `passwd`, `Bearer ...`, private
  key headers (`-----BEGIN ... PRIVATE KEY-----`), `.pem`/`.p12` contents,
  database URLs with embedded credentials (`://user:pass@host`), JWTs
  (`eyJ...` three dot-separated base64 segments), Slack/GitHub/Stripe tokens
  (`xox...`, `ghp_...`, `sk_live_...`).
- **High-entropy strings** — long random-looking base64/hex assigned to a
  variable are suspect even without a keyword.
- **Exclusions** — obvious placeholders (`your-key-here`, `xxxx`, `example`,
  `changeme`, `<...>`) and values already present in a committed `.env.example`
  are likely false positives; note them but don't hard-stop on them.

**On a likely hit → HARD STOP:**
- Print the `file:line`, the pattern class, and the matched value **masked**
  (e.g. `AKIA****************`).
- Do **not** spawn the agent. Do **not** share the diff. Tell the user to
  remove/rotate the secret and re-run, or confirm it's a false positive.
- End the skill here.

**If clean → proceed to Step 3.**

## Step 3 — Deeper semantic security pass

Only reached if Step 2 is clean. Spawn the `secrets-reviewer` agent with the
now-cleared snapshot. It reviews for security issues that aren't literal secrets:
injection (SQL/command/template), missing authz checks on new endpoints/handlers,
unsafe deserialization, path traversal, SSRF, weakened crypto, permissive CORS,
disabled TLS verification, and secrets that should be read from env/secret-store
but are being hardcoded structurally.

## Step 4 — Report

Print the local-scan result + the agent's findings (confidence ≥80 only), each
tagged `BLOCKER` / `WARNING` / `NIT` with file:line and a fix, and a dimension
verdict: **BLOCK** if any secret or exploitable issue, **WARN** for hardening
nits, **PASS** if clean. Advises only — never pushes. Clean up any scratch files.
