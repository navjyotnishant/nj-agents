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
#   ./install.sh --check-only    # only check global/CLAUDE.md is in sync; install nothing
#
# Idempotent: re-running relinks. It only ever touches symlinks that point back
# into THIS repo — it never deletes a real file or a link owned by something else.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_ROOT="$HOME/.claude"
UNINSTALL=0
CHECK_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project) TARGET_ROOT="$(cd "$2" && pwd)/.claude"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    --check-only) CHECK_ONLY=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

SKILLS_SRC="$REPO_DIR/skills"
AGENTS_SRC="$REPO_DIR/agents"
GLOBAL_MD_SRC="$REPO_DIR/global/CLAUDE.md"
SKILLS_DST="$TARGET_ROOT/skills"
AGENTS_DST="$TARGET_ROOT/agents"
GLOBAL_MD_DST="$TARGET_ROOT/CLAUDE.md"

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

# global/CLAUDE.md lists skills and agents by hand (it is prose, not a glob), so it
# silently goes stale when one is added or renamed — a skill missing from it stays
# invisible in other repos. Compare the tables against what actually ships and warn.
# Advisory only: never edits the file, never fails the install.
check_guidance_sync() {
  [ -f "$GLOBAL_MD_SRC" ] || return 0
  local listed actual missing stale rc=0

  # Skill rows look like:  | `/name` | ... |   Agents are cited as `name` in col 3.
  listed="$(grep -o '^| `/[a-z0-9-]*`' "$GLOBAL_MD_SRC" | tr -d '|` /' | sort -u)"
  actual="$(for d in "$SKILLS_SRC"/*/; do basename "$d"; done | sort -u)"
  missing="$(comm -13 <(echo "$listed") <(echo "$actual") | tr '\n' ' ')"
  stale="$(comm -23 <(echo "$listed") <(echo "$actual") | tr '\n' ' ')"

  if [ -n "${missing// }" ] || [ -n "${stale// }" ]; then
    echo "  ! global/CLAUDE.md is out of sync with skills/:" >&2
    [ -n "${missing// }" ] && echo "      not listed (invisible in other repos): $missing" >&2
    [ -n "${stale// }" ]   && echo "      listed but no longer exists:          $stale" >&2
    rc=1
  fi

  listed="$(grep -o '`[a-z0-9-]*`' "$GLOBAL_MD_SRC" | tr -d '`' | sort -u)"
  actual="$(for f in "$AGENTS_SRC"/*.md; do basename "$f" .md; done | sort -u)"
  missing="$(comm -13 <(echo "$listed") <(echo "$actual") | tr '\n' ' ')"
  if [ -n "${missing// }" ]; then
    echo "  ! global/CLAUDE.md does not mention these agents: $missing" >&2
    rc=1
  fi

  [ "$rc" = "0" ] && echo "  guidance file in sync ($(echo "$actual" | wc -w | tr -d ' ') agents, $(ls -d "$SKILLS_SRC"/*/ | wc -l | tr -d ' ') skills)"
  return 0
}

if [ "$CHECK_ONLY" = "1" ]; then
  echo "Checking global/CLAUDE.md against skills/ and agents/ ..."
  check_guidance_sync
  exit 0
fi

if [ "$UNINSTALL" = "1" ]; then
  echo "Uninstalling nj-agents symlinks from $TARGET_ROOT ..."
  for d in "$SKILLS_SRC"/*/; do remove_if_ours "$SKILLS_DST/$(basename "$d")"; done
  for f in "$AGENTS_SRC"/*.md; do remove_if_ours "$AGENTS_DST/$(basename "$f")"; done
  remove_if_ours "$GLOBAL_MD_DST"
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

# Guidance file: tells Claude the suite exists and when to reach for it, in EVERY
# repo. Never clobbers a hand-written CLAUDE.md (link_one guards that).
link_one "$GLOBAL_MD_SRC" "$GLOBAL_MD_DST"

check_guidance_sync

echo "Done. Restart Claude Code (or reload) to pick up the new skills/agents."
echo "Try:  /pre-push-review   (or /review-secrets, /review-correctness, ...)"
