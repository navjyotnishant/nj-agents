#!/usr/bin/env bash
#
# nj-agents installer — symlinks this repo's skills and agents into a Claude Code
# config directory so editing the repo updates them everywhere.
#
# Usage:
#   ./install.sh                 # install globally into ~/.claude/
#   ./install.sh --project DIR   # install into DIR/.claude/ (per-project)
#   ./install.sh --uninstall     # remove symlinks this installer created (global)
#   ./install.sh --project DIR --uninstall
#
# Idempotent: re-running relinks. It only ever touches symlinks that point back
# into THIS repo — it never deletes a real file or a link owned by something else.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_ROOT="$HOME/.claude"
UNINSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project) TARGET_ROOT="$(cd "$2" && pwd)/.claude"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

SKILLS_SRC="$REPO_DIR/skills"
AGENTS_SRC="$REPO_DIR/agents"
SKILLS_DST="$TARGET_ROOT/skills"
AGENTS_DST="$TARGET_ROOT/agents"

# Remove a symlink only if it points back into this repo (safe uninstall).
remove_if_ours() {
  local link="$1"
  if [ -L "$link" ]; then
    local dest; dest="$(readlink "$link")"
    case "$dest" in
      "$REPO_DIR"/*) rm "$link"; echo "  removed $link" ;;
      *) echo "  skipped $link (not ours → $dest)" ;;
    esac
  fi
}

link_one() {
  local src="$1" dst="$2"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    echo "  ! $dst exists and is NOT a symlink — leaving it alone" >&2
    return
  fi
  ln -sfn "$src" "$dst"
  echo "  linked $dst -> $src"
}

if [ "$UNINSTALL" = "1" ]; then
  echo "Uninstalling nj-agents symlinks from $TARGET_ROOT ..."
  for d in "$SKILLS_SRC"/*/; do remove_if_ours "$SKILLS_DST/$(basename "$d")"; done
  for f in "$AGENTS_SRC"/*.md; do remove_if_ours "$AGENTS_DST/$(basename "$f")"; done
  echo "Done."
  exit 0
fi

echo "Installing nj-agents into $TARGET_ROOT ..."
mkdir -p "$SKILLS_DST" "$AGENTS_DST"

# Skills: one directory per skill (each contains SKILL.md).
for d in "$SKILLS_SRC"/*/; do
  link_one "${d%/}" "$SKILLS_DST/$(basename "$d")"
done

# Agents: flat .md files.
for f in "$AGENTS_SRC"/*.md; do
  link_one "$f" "$AGENTS_DST/$(basename "$f")"
done

echo "Done. Restart Claude Code (or reload) to pick up the new skills/agents."
echo "Try:  /pre-push-review   (or /review-secrets, /review-correctness, ...)"
