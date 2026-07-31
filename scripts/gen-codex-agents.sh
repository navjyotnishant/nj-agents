#!/usr/bin/env bash
#
# Generate Codex custom-agent TOML from this repo's markdown agents.
#
#   scripts/gen-codex-agents.sh <output-dir>
#
# Codex reads agents as TOML (~/.codex/agents/<name>.toml), not markdown with
# YAML frontmatter — a different FORMAT, not just a different path, so the
# agents/*.md files cannot be symlinked there the way skills can. This emits the
# TOML instead, at install time, from the same canonical markdown.
#
# The schema follows Codex's own `migrate-to-codex` skill, which ships a
# converter at ~/.codex/vendor_imports/.../migrate/agents.py:
#
#   name                    = "<agent name>"
#   description             = "<one line, used to decide when to delegate>"
#   developer_instructions  = '''<the agent body — its system prompt>'''
#
# with optional model / model_reasoning_effort / sandbox_mode, all omitted here:
# an agent inherits the session's model deliberately (see agents/*.md).
#
# NOTE ON `tools:` — Codex does not accept a tool allowlist as a permission the
# way Gemini does. The vendor converter is explicit that Claude tool lists are
# "preserved as prompt guidance, not Codex permissions", so this does the same:
# the list is stated inside developer_instructions where the model will read it.
# The real enforcement on Codex is sandbox_mode and [permissions], which are a
# per-user decision and deliberately not set here.
#
# Generated files are build artifacts. They are overwritten on every run, are
# never committed, and carry a header saying so.

set -euo pipefail

OUT="${1:?usage: gen-codex-agents.sh <output-dir>}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_SRC="$REPO_DIR/agents"

[ -d "$AGENTS_SRC" ] || { echo "no agents/ directory at $AGENTS_SRC" >&2; exit 1; }
mkdir -p "$OUT"

# TOML basic strings need " and \ escaped. Multi-line literal strings ('''…''')
# need no escaping at all, which is why the body uses them — an agent body is
# full of quotes, backslashes and backticks, and escaping all of it would be
# both lossy and unreadable.
esc_basic() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

count=0
for f in "$AGENTS_SRC"/*.md; do
  [ -f "$f" ] || continue
  name="$(basename "$f" .md)"

  # Frontmatter is everything between the first two --- lines; the body is the
  # rest, and becomes the agent's system prompt.
  fm="$(awk '/^---$/{n++; next} n==1' "$f")"
  body="$(awk '/^---$/{n++; next} n>=2' "$f")"

  desc="$(printf '%s' "$fm" | grep -m1 '^description:' | sed 's/^description: *//' || true)"
  # Descriptions are quoted in the source (valid YAML); strip the wrapper and
  # unescape, since TOML will re-escape them its own way.
  case "$desc" in
    '"'*'"') desc="${desc#\"}"; desc="${desc%\"}"; desc="$(printf '%s' "$desc" | sed 's/\\"/"/g')" ;;
  esac
  # Codex uses the description to decide when to delegate. Ours embed an
  # <example> block for Claude Code's benefit, which is noise here — cut at it.
  desc="${desc%%\\n\\n<example>*}"
  desc="${desc%%<example>*}"

  tools="$(printf '%s' "$fm" | grep -m1 '^tools:' | sed 's/^tools: *//' || true)"

  # A ''' anywhere in the body would close the literal string early and emit
  # silently-corrupt TOML — the file would still parse, just truncated. No agent
  # contains one today; fail loudly rather than let one slip through later.
  case "$body" in
    *"'''"*)
      echo "agents/$name.md contains ''' — cannot be emitted as a TOML literal string." >&2
      echo "Rewrite that fence (use ~~~ or indent it) and re-run." >&2
      exit 1 ;;
  esac

  {
    echo "# GENERATED — do not edit."
    echo "# Source: agents/$name.md in the nj-agents repo."
    echo "# Regenerate with: ./install.sh --runner codex"
    echo "# Edits here are overwritten and are invisible to every other runner."
    echo ""
    echo "name = \"$(esc_basic "$name")\""
    echo "description = \"$(esc_basic "$desc")\""
    echo ""
    echo "developer_instructions = '''"
    if [ -n "$tools" ]; then
      # Stated as guidance, not permission — see the note at the top.
      echo "## Tools"
      echo ""
      echo "You may use these tools: $tools."
      echo "This agent does not need any others; if a task seems to require one,"
      echo "say so rather than reaching for it."
      echo ""
    fi
    printf '%s\n' "$body"
    echo "'''"
  } > "$OUT/$name.toml"

  count=$((count + 1))
done

echo "$count"
