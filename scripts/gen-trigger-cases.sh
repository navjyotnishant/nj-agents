#!/usr/bin/env bash
#
# Generate trigger-cases.json: positive routing cases for every skill, extracted
# from its own frontmatter `description` — the quoted trigger phrases each skill
# already writes for a human/model to recognize itself by (e.g. "create a task").
#
#   scripts/gen-trigger-cases.sh > /tmp/trigger-cases.json
#
# This is a POINTER-FREE extraction, not hand-authored data: every case's prompt
# text and expected skill both come straight from the skill's own SKILL.md, so
# there is nothing here that can drift independently of the skill it describes.
# check_description_routing (check.sh) regenerates this at check time into a
# tempdir rather than trusting a committed copy — same reason gen-cursor-rule.sh
# and gen-codex-agents.sh are never committed as their own output.
#
# Requires jq. Skills whose description has no quoted phrase are skipped with a
# warning to stderr rather than silently omitted from coverage.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_SRC="$REPO_DIR/skills"

command -v jq >/dev/null 2>&1 || { echo "gen-trigger-cases.sh: jq required" >&2; exit 1; }

cases="[]"
for dir in "$SKILLS_SRC"/*/; do
  name="$(basename "${dir%/}")"
  skill_md="$dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  # Frontmatter is delimited by --- lines; description is a single YAML scalar
  # line (this repo's convention — no multi-line block scalars in practice).
  # Some descriptions are YAML double-quoted with escaped \"inner\" quotes around
  # each trigger phrase — strip the outer quote and unescape before extracting,
  # or the quote-extraction below grabs garbage at the first escaped quote.
  desc="$(awk '/^---$/{n++; next} n==1 && /^description:/{sub(/^description: */,""); print; exit}' "$skill_md")"
  desc="$(printf '%s' "$desc" | sed -e 's/^"//' -e 's/"$//' -e 's/\\"/"/g')"
  [ -n "$desc" ] || { echo "gen-trigger-cases.sh: $name has no description line" >&2; continue; }

  # Extract every "quoted phrase" of at least 5 chars — the same trigger
  # vocabulary a model reads to decide whether this skill matches a prompt.
  # `grep -oE` exits 1 on no match (a description with no quoted phrase at all,
  # e.g. one that regressed to something generic) — under set -e that would kill
  # the whole script before the empty-phrases guard below ever runs, so `|| true`.
  phrases="$(printf '%s' "$desc" | grep -oE '"[^"]{5,80}"' | sed 's/^"//; s/"$//' || true)"
  [ -n "$phrases" ] || { echo "gen-trigger-cases.sh: $name has no quoted trigger phrases" >&2; continue; }

  while IFS= read -r phrase; do
    [ -n "$phrase" ] || continue
    cases="$(jq --arg p "$phrase" --arg s "$name" '. + [{prompt:$p, skill:$s}]' <<<"$cases")"
  done <<<"$phrases"
done

jq -n --argjson c "$cases" '{cases:$c}'
