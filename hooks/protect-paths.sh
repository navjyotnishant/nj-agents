#!/usr/bin/env bash
# PreToolUse hook (Edit|Write): block an edit to a project-declared protected path.
#
# A skill is an advisory control — it makes an edit to a protected path unlikely,
# but nothing stops it. This is the deterministic layer behind that: a frozen
# package, a generated tree, a legacy directory nobody touches by hand gets a real
# gate, not a convention someone has to remember.
#
# Per-project, opt-in: reads .nj-agents/protected-paths.txt at the repo root (one
# glob pattern per line, `#` for comments). No file means no blocking — this must
# never be the reason an edit fails on a machine/repo that never configured it
# (§A5 detect-never-require).
#
# Exit code 2 blocks the tool call (PreToolUse's own contract); the stderr text is
# the message Claude sees. Exit 0 otherwise, always — a hook that errors on its own
# bugs is worse than one that silently no-ops.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // ""' 2>/dev/null || true)"
case "$tool_name" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

cwd="$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null || true)"
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)"
[ -n "$file_path" ] || exit 0

# Resolve the repo root the same way check.sh/install.sh do — from cwd, not from
# this script's own location, since the hook runs from the session's working dir.
repo_root="$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$repo_root" ] || exit 0

config="$repo_root/.nj-agents/protected-paths.txt"
[ -f "$config" ] || exit 0

# Resolve both through their real (symlink-free) ancestor directory before
# comparing. `git rev-parse --show-toplevel` and the tool's own file_path can
# disagree on a symlinked ancestor (macOS's /tmp -> /private/tmp being the common
# case) even when they name the same file — a naive string-prefix strip then
# silently fails to match anything, and the hook never blocks. `realpath -m`/
# `--canonicalize-missing` would do this in one call but neither flag exists in
# BSD (macOS) realpath, and Write can create a path whose directory doesn't exist
# yet either (a new nested dir) — so walk up to the nearest existing ancestor,
# resolve THAT, and reattach the rest of the path unresolved (a not-yet-created
# component has no symlink to canonicalize).
resolve_nearest_existing() {
  local p="$1" suffix=""
  while [ -n "$p" ] && [ "$p" != "/" ] && [ ! -d "$p" ]; do
    suffix="/$(basename "$p")$suffix"
    p="$(dirname "$p")"
  done
  [ -d "$p" ] || { echo "$1"; return; }
  local resolved; resolved="$(cd "$p" 2>/dev/null && pwd -P)" || { echo "$1"; return; }
  printf '%s%s\n' "$resolved" "$suffix"
}
repo_root_real="$(resolve_nearest_existing "$repo_root")"
file_path_real="$(resolve_nearest_existing "$(dirname "$file_path")")/$(basename "$file_path")"

# Path relative to the repo root, since patterns in the config are written that
# way (matching .gitignore's own convention, which this file is modeled on).
rel_path="${file_path_real#"$repo_root_real"/}"

while IFS= read -r pattern; do
  pattern="${pattern%%#*}"                    # strip a trailing comment
  pattern="$(printf '%s' "$pattern" | sed 's/[[:space:]]*$//')"  # trim trailing ws
  [ -n "$pattern" ] || continue
  # shellcheck disable=SC2254 # intentional glob match, not a literal string compare
  case "$rel_path" in
    $pattern)
      echo "Blocked by .nj-agents/protected-paths.txt: '$rel_path' matches protected pattern '$pattern'." >&2
      echo "This path is declared protected for this project. If the edit is intentional, update .nj-agents/protected-paths.txt first." >&2
      exit 2
      ;;
  esac
done < "$config"

exit 0
