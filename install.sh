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
#   ./install.sh --with-hooks    # ALSO register the skill-suggestion hook in settings.json
#   ./install.sh --git-hooks     # install this repo's own .git/hooks (per-clone, not committed)
#
# Idempotent: re-running relinks. It only ever touches symlinks that point back
# into THIS repo — it never deletes a real file or a link owned by something else.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_ROOT="$HOME/.claude"
UNINSTALL=0
CHECK_ONLY=0
WITH_HOOKS=0
GIT_HOOKS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project) TARGET_ROOT="$(cd "$2" && pwd)/.claude"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    --check-only) CHECK_ONLY=1; shift ;;
    --with-hooks) WITH_HOOKS=1; shift ;;
    --git-hooks) GIT_HOOKS=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

SKILLS_SRC="$REPO_DIR/skills"
AGENTS_SRC="$REPO_DIR/agents"
GLOBAL_MD_SRC="$REPO_DIR/global/CLAUDE.md"
HOOKS_SRC="$REPO_DIR/hooks"
SKILLS_DST="$TARGET_ROOT/skills"
AGENTS_DST="$TARGET_ROOT/agents"
GLOBAL_MD_DST="$TARGET_ROOT/CLAUDE.md"
HOOKS_DST="$TARGET_ROOT/hooks"
SETTINGS="$TARGET_ROOT/settings.json"

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

# Wiring the suggestion hook means editing settings.json — the user's file, not
# ours. Idempotent: if an entry already points at this script, do nothing rather
# than adding a second one. Needs jq to edit JSON safely; without it, print the
# snippet and let the user paste it.
register_hook() {
  local hook="$HOOKS_DST/suggest-skills.sh"
  local snippet='{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"'"$hook"'","timeout":10}]}]}'
  if ! command -v jq >/dev/null 2>&1; then
    echo "  ! jq not found — add this to $SETTINGS by hand under \"hooks\":" >&2
    echo "      $snippet" >&2
    return 0
  fi
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  if jq -e --arg h "$hook" '.hooks.UserPromptSubmit // [] | any(.hooks[]?.command == $h)' "$SETTINGS" >/dev/null 2>&1; then
    echo "  suggestion hook already registered"
    return 0
  fi
  local tmp; tmp="$(mktemp)"
  jq --arg h "$hook" '.hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [{hooks:[{type:"command",command:$h,timeout:10}]}])' \
    "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "  registered the suggestion hook in ${SETTINGS/#$HOME/~}"
}

# Validation lives in check.sh (it globs, so it covers new skills automatically).
# --check-only stays advisory here: it reports but never fails the install.
# .git/hooks is NOT tracked by git, so a hook cannot ship with a clone. Keep the
# source under hooks/git/ and copy it in on request — this is the local stand-in
# for branch protection, which needs GitHub Pro on a private repo.
if [ "$GIT_HOOKS" = "1" ]; then
  gitdir="$(git -C "$REPO_DIR" rev-parse --git-dir 2>/dev/null)" || {
    echo "  ! not a git repository — nothing to install" >&2; exit 2; }
  for h in "$REPO_DIR"/hooks/git/*; do
    [ -f "$h" ] || continue
    dst="$gitdir/hooks/$(basename "$h")"
    if [ -e "$dst" ] && ! cmp -s "$h" "$dst"; then
      echo "  ! $dst exists and differs — leaving it alone" >&2
      continue
    fi
    cp "$h" "$dst" && chmod +x "$dst" && echo "  installed $dst"
  done
  exit 0
fi

if [ "$CHECK_ONLY" = "1" ]; then
  exec "$REPO_DIR/check.sh"
fi

if [ "$UNINSTALL" = "1" ]; then
  echo "Uninstalling nj-agents symlinks from $TARGET_ROOT ..."
  for d in "$SKILLS_SRC"/*/; do remove_if_ours "$SKILLS_DST/$(basename "$d")"; done
  for f in "$AGENTS_SRC"/*.md; do remove_if_ours "$AGENTS_DST/$(basename "$f")"; done
  for f in "$HOOKS_SRC"/*.sh; do [ -f "$f" ] && remove_if_ours "$HOOKS_DST/$(basename "$f")"; done
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

# Hooks: shipped here so they survive a reinstall, but only WIRED on request —
# registering one edits the user's settings.json, which the installer never does
# behind their back.
if [ -d "$HOOKS_SRC" ]; then
  mkdir -p "$HOOKS_DST"
  for f in "$HOOKS_SRC"/*.sh; do
    [ -f "$f" ] || continue
    link_one "$f" "$HOOKS_DST/$(basename "$f")"
  done
fi
[ "$WITH_HOOKS" = "1" ] && register_hook

"$REPO_DIR/check.sh" || true

echo "Done. Restart Claude Code (or reload) to pick up the new skills/agents."
echo "Try:  /pre-push-review   (or /review-secrets, /review-correctness, ...)"
