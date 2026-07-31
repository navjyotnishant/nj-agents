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
# Skills are portable as-is — SKILL.md is an open standard. Agents mostly are too,
# with one exception: Codex reads them as TOML, not markdown with YAML frontmatter,
# so for that runner they are GENERATED at install time from the same canonical
# agents/*.md (scripts/gen-codex-agents.sh). Generated files are build artifacts:
# rewritten on every install, never committed, and they say so in their header.
#
# Cursor guidance is generated too, for the same reason: it reads .mdc with real
# frontmatter, not plain markdown. Its rule is a POINTER at global/AGENTS.md
# rather than a copy — Cursor's own create-rule skill says rules should stay
# under 50 lines, and an always-on 240-line rule would cost context on every
# request (scripts/gen-cursor-rule.sh).
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

# Codex reads agents as TOML, so its agents are generated rather than linked
# (see the agents block below). Cursor registers subagents separately.
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

# Tallies, so the summary can say what actually happened rather than scrolling 49
# near-identical "linked ..." lines past the one line that mattered.
N_NEW=0; N_SAME=0; N_REPAIRED=0; N_BLOCKED=0; N_GENERATED=0; N_RULE=0
BLOCKED_LIST=""

link_one() {
  local src="$1" dst="$2" cur
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    # A real file the user wrote. Never clobber it — but do not let it pass in
    # silence either: it means their copy has stopped tracking the repo.
    N_BLOCKED=$((N_BLOCKED + 1))
    BLOCKED_LIST="$BLOCKED_LIST  $dst
"
    return
  fi
  if [ -L "$dst" ]; then
    cur="$(readlink "$dst")"
    if [ "$cur" = "$src" ]; then
      N_SAME=$((N_SAME + 1))
    elif [ -e "$dst" ]; then
      N_NEW=$((N_NEW + 1))          # repointed at a different live target
    else
      # Dangling — e.g. the source was renamed since the last install. This is
      # exactly the case a silent re-link would hide, and a broken guidance link
      # gives no error at run time, so it is worth calling out.
      N_REPAIRED=$((N_REPAIRED + 1))
    fi
  else
    N_NEW=$((N_NEW + 1))
  fi
  ln -sfn "$src" "$dst"
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
  # Generated Codex agents are real files, not symlinks, so remove_if_ours will
  # not touch them. Only delete ones carrying our generated header — a .toml the
  # user wrote by hand must survive an uninstall.
  for f in "$AGENTS_SRC"/*.md; do
    t="$AGENTS_DST/$(basename "$f" .md).toml"
    [ -f "$t" ] && head -2 "$t" | grep -q "Source: agents/.* in the nj-agents repo" && {
      rm "$t"; echo "  removed $t"
    }
  done
  for f in "$HOOKS_SRC"/*.sh; do [ -f "$f" ] && remove_if_ours "$HOOKS_DST/$(basename "$f")"; done
  [ -n "$GLOBAL_MD_DST" ] && remove_if_ours "$GLOBAL_MD_DST"
  # Generated, not linked — remove_if_ours would skip it. Only ours carries the
  # generator's own marker line.
  r="$TARGET_ROOT/rules/nj-agents.mdc"
  [ -f "$r" ] && grep -q "gen-cursor-rule.sh" "$r" && { rm "$r"; echo "  removed $r"; }
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

# Agents. Markdown symlinks where the runner reads that format; generated TOML
# for Codex, which does not. Generation is the exception, not the pattern — it
# exists only because the FORMAT differs, and the generated files are build
# artifacts that say so in their own header.
if [ "$INSTALL_AGENTS" = "1" ]; then
  for f in "$AGENTS_SRC"/*.md; do
    link_one "$f" "$AGENTS_DST/$(basename "$f")"
  done
elif [ "$RUNNER" = "codex" ]; then
  mkdir -p "$AGENTS_DST"
  if n_gen="$("$REPO_DIR/scripts/gen-codex-agents.sh" "$AGENTS_DST")"; then
    N_GENERATED="$n_gen"
  else
    echo "  ! agent generation failed — Codex will have skills but no agents" >&2
  fi
else
  case "$RUNNER" in
    cursor) echo "  - agents skipped: Cursor subagents are registered separately (NAV-152)" ;;
  esac
fi

# Guidance file: tells the agent the suite exists and when to reach for it, in
# EVERY repo. Linked under whatever filename this runner reads. Never clobbers a
# hand-written file (link_one guards that).
if [ -n "$GLOBAL_MD_DST" ]; then
  link_one "$GLOBAL_MD_SRC" "$GLOBAL_MD_DST"
elif [ "$RUNNER" = "cursor" ]; then
  # Cursor wants .mdc with real frontmatter, and its own create-rule skill says
  # rules should stay "under 50 lines" — so this is a generated pointer at the
  # 240-line guidance, not a copy of it.
  if n_rule="$("$REPO_DIR/scripts/gen-cursor-rule.sh" "$TARGET_ROOT/rules")"; then
    N_RULE="$n_rule"
  else
    echo "  ! Cursor rule generation failed — the skills install, but Cursor" >&2
    echo "    will not know to prefer them" >&2
  fi
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

# Anything in the target that is NOT a link back here is invisible to this repo:
# not version-controlled, not installed for other runners, not covered by
# check.sh. Usually it is a skill written directly into the config dir and then
# forgotten. Report it — the install is the only moment anyone looks here.
ORPHANS=""
scan_orphans() {
  local dir="$1" kind="$2" f
  [ -d "$dir" ] || return 0
  for f in "$dir"/*; do
    [ -e "$f" ] || continue
    [ -L "$f" ] && continue
    # Already reported above as "not replaced" — it shadows a repo file, which is
    # a different problem from being an orphan, and saying both invites confusion.
    case "$BLOCKED_LIST" in *"  $f"$'\n'*) continue ;; esac
    ORPHANS="$ORPHANS  $kind  ${f#$HOME/}
"
  done
}
scan_orphans "$SKILLS_DST" "skill"
[ "$INSTALL_AGENTS" = "1" ] && scan_orphans "$AGENTS_DST" "agent"
scan_orphans "$HOOKS_DST" "hook "

echo ""
echo "Summary"
echo "  runner        $RUNNER  ($TARGET_ROOT)"
echo "  linked        $N_NEW new, $N_SAME already current$([ "$N_REPAIRED" -gt 0 ] && echo ", $N_REPAIRED repaired (were dangling)")"
[ "$N_GENERATED" -gt 0 ] && \
  echo "  generated     $N_GENERATED agent .toml files (Codex reads TOML, not markdown) —
                build artifacts, rewritten every install; do not edit them"
[ -n "$GLOBAL_MD_DST" ] && echo "  guidance      ${GLOBAL_MD_DST#$HOME/} -> ${GLOBAL_MD_SRC#$REPO_DIR/}"
[ "$N_RULE" -gt 0 ] && \
  echo "  guidance      rules/nj-agents.mdc ($N_RULE lines, generated) — a pointer at
                global/AGENTS.md, since Cursor rules should stay under 50 lines"

if [ "$N_BLOCKED" -gt 0 ]; then
  echo ""
  echo "  Not replaced — these are real files, not links, so your copy no longer"
  echo "  tracks this repo. Delete one and re-run to adopt the repo's version:"
  printf '%s' "$BLOCKED_LIST"
fi

if [ -n "$ORPHANS" ]; then
  echo ""
  echo "  Present here but NOT in this repo — not version-controlled, and not"
  echo "  installed for any other runner. Move them into the repo to keep them:"
  printf '%s' "$ORPHANS"
fi

# check.sh itself installs into a temp dir to verify the runner layout, so it sets
# NJ_AGENTS_NO_CHECK to stop us calling it straight back and recursing forever.
echo ""
[ -n "${NJ_AGENTS_NO_CHECK:-}" ] || "$REPO_DIR/check.sh" || true

echo ""
echo "Done. Restart $RUNNER (or reload) to pick up the new skills/agents."
echo "Try:  /pre-push-review   (or /review-secrets, /review-correctness, ...)"
