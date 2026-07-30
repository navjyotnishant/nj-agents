#!/usr/bin/env bash
# Build the fixture repos from scratch. They are generated, not committed — a git
# repo inside a git repo is a submodule trap, and these must be disposable.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

new_repo() {
  local d="$HERE/$1"; rm -rf "$d"; mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email fixture@example.test
  git -C "$d" config user.name "Fixture"
  git -C "$d" config commit.gpgsign false
  echo "$d"
}

# dirty — a small uncommitted change for the review class to look at.
d="$(new_repo dirty)"
printf 'def add(a, b):\n    return a + b\n' > "$d/calc.py"
git -C "$d" add -A && git -C "$d" commit -qm "init"
printf 'def add(a, b):\n    return a + b\n\ndef div(a, b):\n    return a / b\n' > "$d/calc.py"

# with-changelog / without-changelog — the two §A4 placement rungs.
d="$(new_repo with-changelog)"
printf '# Changelog\n\n## [Unreleased]\n\n### Added\n- an existing entry\n' > "$d/CHANGELOG.md"
printf 'x = 1\n' > "$d/app.py"
git -C "$d" add -A && git -C "$d" commit -qm "feat: add app"

# A tag + commits after it, so /changelog has a real "since the last release" range
# to summarise. Without one it has nothing to write, and an empty result would look
# like a contract violation when it is just an empty input.
d="$(new_repo without-changelog)"
printf 'x = 1\n' > "$d/app.py"
git -C "$d" add -A && git -C "$d" commit -qm "chore: init"
git -C "$d" tag -a v0.1.0 -m "v0.1.0"
printf 'x = 1\ny = 2\n' > "$d/app.py"
git -C "$d" add -A && git -C "$d" commit -qm "feat: add y"
printf 'def z():\n    return 3\n' > "$d/z.py"
git -C "$d" add -A && git -C "$d" commit -qm "fix: handle z"

echo "fixtures built in $HERE"
