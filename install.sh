#!/usr/bin/env bash
#
# nj-agents installer — symlinks this repo's skills and agents into an AI coding
# agent's config directory so editing the repo updates them everywhere.
#
# Usage:
#   ./install.sh                 # install globally for Claude Code (~/.claude/)
#   ./install.sh --runner NAME   # install for another runner (see below)
#   ./install.sh --project DIR   # install into DIR/<runner-dir>/ (per-project)
#   ./install.sh --uninstall     # remove symlinks this installer created (global)
#   ./install.sh --project DIR --uninstall
#   ./install.sh --check-only    # only check global/AGENTS.md is in sync; install nothing
#   ./install.sh --with-hooks    # ALSO register the skill-suggestion hook in settings.json
#   ./install.sh --git-hooks     # install this repo's own .git/hooks (per-clone, not committed)
#
# Runners (--runner):
#   claude   ~/.claude    CLAUDE.md   default; unchanged from before
#   codex    ~/.codex     AGENTS.md
#   cursor   ~/.cursor    (rules)     see the note below
#   gemini   ~/.gemini    GEMINI.md
#   agents   ~/.agents    AGENTS.md   the vendor-neutral path Codex and Gemini both read
#
# Because everything is a SYMLINK back into this clone, you do not pick one
# runner: install for each one you use and they all read the same files. Edit a
# skill once and every runner sees it — there is nothing to sync.
#
# Skills and agents are portable as-is. Two things are NOT, and are handled by
# their own stories rather than silently half-working here:
#   - Codex reads agents as TOML, not markdown (NAV-159)
#   - Cursor reads guidance as .mdc with real frontmatter, not plain md (NAV-152)
# Until those land, --runner codex installs skills + guidance but not agents, and
# --runner cursor installs skills only. Both say so when they run.
#
# Idempotent: re-running relinks. It only ever touches symlinks that point back
# into THIS repo — it never deletes a real file or a link owned by something else.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="claude"
PROJECT_DIR=""
UNINSTALL=0
CHECK_ONLY=0
WITH_HOOKS=0
GIT_HOOKS=0

VALID_RUNNERS="claude codex cursor gemini agents"

while [ $# -gt 0 ]; do
  case "$1" in
    --runner)
      [ $# -ge 2 ] || { echo "--runner needs a value ($VALID_RUNNERS)" >&2; exit 2; }
      RUNNER="$2"; shift 2 ;;
    --project) PROJECT_DIR="$(cd "$2" && pwd)"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    --check-only) CHECK_ONLY=1; shift ;;
    --with-hooks) WITH_HOOKS=1; shift ;;
    --git-hooks) GIT_HOOKS=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Validate before doing anything — a typo'd runner must not silently install to
# a directory nothing reads.
case " $VALID_RUNNERS " in
  *" $RUNNER "*) ;;
  *) echo "Unknown runner: $RUNNER" >&2
     echo "Valid runners: $VALID_RUNNERS" >&2
     exit 2 ;;
esac

# Per-runner layout. Only two things vary: the config directory name and the
# filename the runner reads its global guidance from. Everything else derives.
case "$RUNNER" in
  claude) RUNNER_DIR=".claude"; GUIDANCE_NAME="CLAUDE.md" ;;
  codex)  RUNNER_DIR=".codex";  GUIDANCE_NAME="AGENTS.md" ;;
  cursor) RUNNER_DIR=".cursor"; GUIDANCE_NAME="" ;;   # .mdc — NAV-152
  gemini) RUNNER_DIR=".gemini"; GUIDANCE_NAME="GEMINI.md" ;;
  agents) RUNNER_DIR=".agents"; GUIDANCE_NAME="AGENTS.md" ;;
esac

# Codex reads agents as TOML, not markdown, so symlinking .md files there would
# create a directory of files it silently ignores. Skip until NAV-159 lands.
INSTALL_AGENTS=1
[ "$RUNNER" = "codex" ] && INSTALL_AGENTS=0
[ "$RUNNER" = "cursor" ] && INSTALL_AGENTS=0

if [ -n "$PROJECT_DIR" ]; then
  TARGET_ROOT="$PROJECT_DIR/$RUNNER_DIR"
else
  TARGET_ROOT="$HOME/$RUNNER_DIR"
fi

SKILLS_SRC="$REPO_DIR/skills"
AGENTS_SRC="$REPO_DIR/agents"
GLOBAL_MD_SRC="$REPO_DIR/global/AGENTS.md"
HOOKS_SRC="$REPO_DIR/hooks"
SKILLS_DST="$TARGET_ROOT/skills"
AGENTS_DST="$TARGET_ROOT/agents"
GLOBAL_MD_DST="${GUIDANCE_NAME:+$TARGET_ROOT/$GUIDANCE_NAME}"
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
  echo "Uninstalling nj-agents symlinks from $TARGET_ROOT (runner: $RUNNER) ..."
  for d in "$SKILLS_SRC"/*/; do remove_if_ours "$SKILLS_DST/$(basename "$d")"; done
  # Agents are removed unconditionally, even for runners the installer now skips:
  # an earlier install (or an earlier version of this script) may have left them,
  # and remove_if_ours only ever touches links pointing back into this repo.
  for f in "$AGENTS_SRC"/*.md; do remove_if_ours "$AGENTS_DST/$(basename "$f")"; done
  for f in "$HOOKS_SRC"/*.sh; do [ -f "$f" ] && remove_if_ours "$HOOKS_DST/$(basename "$f")"; done
  [ -n "$GLOBAL_MD_DST" ] && remove_if_ours "$GLOBAL_MD_DST"
  echo "Done."
  exit 0
fi

echo "Installing nj-agents into $TARGET_ROOT (runner: $RUNNER) ..."
mkdir -p "$SKILLS_DST"
[ "$INSTALL_AGENTS" = "1" ] && mkdir -p "$AGENTS_DST"

# Skills: one directory per skill (each contains SKILL.md). SKILL.md is an open
# standard, so this is the part that works unchanged on every runner.
for d in "$SKILLS_SRC"/*/; do
  link_one "${d%/}" "$SKILLS_DST/$(basename "$d")"
done

# Agents: flat .md files — but only where the runner reads that format.
if [ "$INSTALL_AGENTS" = "1" ]; then
  for f in "$AGENTS_SRC"/*.md; do
    link_one "$f" "$AGENTS_DST/$(basename "$f")"
  done
else
  case "$RUNNER" in
    codex)  echo "  - agents skipped: Codex reads agents as TOML, not markdown (NAV-159)" ;;
    cursor) echo "  - agents skipped: Cursor subagents are registered separately (NAV-152)" ;;
  esac
fi

# Guidance file: tells the agent the suite exists and when to reach for it, in
# EVERY repo. Linked under whatever filename this runner reads. Never clobbers a
# hand-written file (link_one guards that).
if [ -n "$GLOBAL_MD_DST" ]; then
  link_one "$GLOBAL_MD_SRC" "$GLOBAL_MD_DST"
else
  echo "  - guidance skipped: Cursor needs .mdc with frontmatter, not plain markdown (NAV-152)"
fi

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

# check.sh itself installs into a temp dir to verify the runner layout, so it sets
# NJ_AGENTS_NO_CHECK to stop us calling it straight back and recursing forever.
[ -n "${NJ_AGENTS_NO_CHECK:-}" ] || "$REPO_DIR/check.sh" || true

echo "Done. Restart $RUNNER (or reload) to pick up the new skills/agents."
echo "Try:  /pre-push-review   (or /review-secrets, /review-correctness, ...)"
