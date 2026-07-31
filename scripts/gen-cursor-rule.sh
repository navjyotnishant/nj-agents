#!/usr/bin/env bash
#
# Generate the Cursor rule that makes this toolkit discoverable in Cursor.
#
#   scripts/gen-cursor-rule.sh <rules-dir>
#
# Cursor reads guidance as `.mdc` in `.cursor/rules/`, with real YAML frontmatter
# (description / globs / alwaysApply) — a different FORMAT from plain markdown,
# so global/AGENTS.md cannot be symlinked here the way CLAUDE.md and GEMINI.md
# can. This emits the rule instead.
#
# It is deliberately a POINTER, not a copy. Cursor's own `create-rule` skill is
# explicit that rules should be "under 50 lines", "one concern per rule", and
# "concise and to the point". global/AGENTS.md is 240 lines of standing rules and
# per-skill tables — converting it wholesale would produce exactly the bloated
# always-on rule that guidance warns against, and would cost context on every
# Cursor request.
#
# So the rule states what the toolkit is, when to reach for it, and where the
# full guidance lives. The skills themselves carry their own instructions and
# Cursor already reads them from ~/.cursor/skills/ — the rule only has to make
# the agent aware they exist.
#
# alwaysApply: true is correct here and matches how CLAUDE.md behaves today:
# this is a universal standard, not a file-type convention, so there is no glob
# that would scope it usefully.
#
# Generated: overwritten on every install, never committed, says so in its body.

set -euo pipefail

OUT="${1:?usage: gen-cursor-rule.sh <rules-dir>}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_SRC="$REPO_DIR/skills"
GUIDANCE="$REPO_DIR/global/AGENTS.md"

mkdir -p "$OUT"

n_skills="$(ls -d "$SKILLS_SRC"/*/ 2>/dev/null | wc -l | tr -d ' ')"

# One line per class, built from the skills themselves so the rule cannot drift
# from what is installed.
class_line() {
  local cls="$1" names=""
  local d n
  for d in "$SKILLS_SRC"/*/; do
    n="$(basename "${d%/}")"
    grep -q "^class: $cls\$" "${d%/}/SKILL.md" 2>/dev/null || continue
    names="$names/$n · "
  done
  printf '%s' "${names% · }"
}

cat > "$OUT/nj-agents.mdc" <<EOF
---
description: The nj-agents SDLC toolkit is installed — prefer its skills over improvising the same task by hand
alwaysApply: true
---

# nj-agents — $n_skills skills for recurring SDLC work

<!-- GENERATED from global/AGENTS.md by scripts/gen-cursor-rule.sh.
     Overwritten by \`./install.sh --runner cursor\`. Edit the source, not this. -->

These skills exist so recurring work is done consistently instead of ad-hoc.
**Prefer the matching skill over improvising**; suggest one when the request
matches, but do not fire them unprompted.

- **Review** (advise only — writes nothing, commits nothing): $(class_line review)
- **Authoring** (writes ONE artifact, then proposes the commit): $(class_line authoring)
- **Workflow** (drafts a PR or commit — never runs git): $(class_line workflow)
- **PM** (writes a tracker item, proposes the create): $(class_line pm)
- **Social** (paste-ready copy — never posts): $(class_line social)

## What every skill guarantees

- **The human decides what gets committed.** Never \`git add\`/\`commit\`/\`push\`/
  \`tag\` on your own initiative — write the artifact and propose the commands.
- **Ground everything in the actual repo.** Never invent an API, path, version, or
  benchmark; unverifiable claims get cut or marked.
- **Degrade, don't fail.** External tools are detected at runtime, never required.
  The one exception is secret scanning, which genuinely blocks without a scanner.
- **No secrets in output**, and nothing leaves the machine.

Each skill carries its full procedure; Cursor reads them from \`~/.cursor/skills/\`.
The complete standing rules — changelog policy, PM tracking, author headers, cost
control — live in \`global/AGENTS.md\` in the nj-agents repo.
EOF

wc -l < "$OUT/nj-agents.mdc" | tr -d ' '
