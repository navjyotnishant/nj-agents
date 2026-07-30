#!/usr/bin/env bash
#
# Assert the behavioral contracts against committed snapshots. NO LLM — this is what
# CI runs, and it costs nothing.
#
# Usage:
#   tests/assert.sh            # assert every snapshot
#   tests/assert.sh --list     # show what is covered, assert nothing
#
# The split matters: tests/run.sh spends money spawning real skill runs and writes
# snapshots/*.json; this reads them back and checks the recorded side effects. A
# missing snapshot is a FAILURE, not a skip — a suite that silently passes when it
# has nothing to check is worse than no suite.
#
# Only NEGATIVE contracts are asserted. "Left no files", "made no commit", "spawned
# no agent" are filesystem and process facts. "Found the right bugs" needs an LLM to
# judge and is deliberately out of scope.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPS="$HERE/snapshots"
FAILED=0
PASSED=0

pass() { PASSED=$((PASSED + 1)); echo "  ok   $1"; }
# The trailing `|| true` matters: without a detail arg the `[ -n ]` test is the last
# command and returns 1, which under `set -e` aborts the loop — so only the first
# failure would ever be reported.
fail() {
  FAILED=$((FAILED + 1))
  echo "  FAIL $1" >&2
  [ -n "${2:-}" ] && echo "         $2" >&2 || true
}

# Snapshots are flat key=value so this stays dependency-free — no jq, no python.
snap_get() {
  local file="$1" key="$2"
  grep -m1 "^$key=" "$file" 2>/dev/null | cut -d= -f2- || true
}

if [ "${1:-}" = "--list" ]; then
  echo "Contracts covered:"
  echo "  review-leaves-no-files    review class writes nothing into the repo"
  echo "  no-commit                 no skill ever commits or stages"
  echo "  secrets-no-scanner        review-secrets BLOCKs, spawns no agent"
  echo "  authoring-one-artifact    authoring writes exactly one file, at its §A4 path"
  exit 0
fi

[ -d "$SNAPS" ] || { echo "tests/snapshots/ missing — run tests/run.sh first" >&2; exit 1; }

# An empty snapshots dir means run.sh never ran. Failing here is the point: CI must
# not report green on a suite that asserted nothing.
count="$(find "$SNAPS" -name '*.snap' -type f | wc -l | tr -d ' ')"
if [ "$count" = "0" ]; then
  echo "no snapshots found in tests/snapshots/ — run tests/run.sh locally first" >&2
  exit 1
fi

# A snapshot that vanishes must fail, not quietly shrink the suite. Without this,
# `rm tests/snapshots/no-commit.snap` leaves CI green with one fewer contract
# checked — a suite that passes by having less to check is the exact failure this
# harness exists to prevent.
EXPECTED="$SNAPS/EXPECTED"
if [ -f "$EXPECTED" ]; then
  while read -r want; do
    case "$want" in ''|\#*) continue ;; esac
    [ -f "$SNAPS/$want.snap" ] || fail "$want: snapshot MISSING" "run tests/run.sh $want"
  done < "$EXPECTED"
fi

echo "Asserting $count snapshot(s) ..."

for snap in "$SNAPS"/*.snap; do
  name="$(basename "$snap" .snap)"
  contract="$(snap_get "$snap" contract)"

  case "$contract" in
    review-leaves-no-files)
      # The strongest assertion in the suite, and pure filesystem: the file listing
      # and git status must be byte-identical before and after the run.
      if [ "$(snap_get "$snap" files_before)" = "$(snap_get "$snap" files_after)" ]; then
        pass "$name: left no files"
      else
        fail "$name: review class wrote into the repo" \
             "before=$(snap_get "$snap" files_before) after=$(snap_get "$snap" files_after)"
      fi
      if [ "$(snap_get "$snap" status_before)" = "$(snap_get "$snap" status_after)" ]; then
        pass "$name: git status unchanged"
      else
        fail "$name: git status changed"
      fi ;;

    no-commit)
      if [ "$(snap_get "$snap" head_before)" = "$(snap_get "$snap" head_after)" ]; then
        pass "$name: HEAD unchanged — nothing was committed"
      else
        fail "$name: a commit was made" \
             "$(snap_get "$snap" head_before) -> $(snap_get "$snap" head_after)"
      fi
      if [ -z "$(snap_get "$snap" staged_after)" ]; then
        pass "$name: nothing staged"
      else
        fail "$name: files were staged" "$(snap_get "$snap" staged_after)"
      fi ;;

    secrets-no-scanner)
      # Structural, not textual: with no scanner on PATH the skill must BLOCK before
      # spawning anything. Counting spawns is far more robust than grepping prose for
      # the word BLOCK, which a summary could mention innocently.
      if [ "$(snap_get "$snap" agents_spawned)" = "0" ]; then
        pass "$name: no agent spawned without a scanner"
      else
        fail "$name: spawned $(snap_get "$snap" agents_spawned) agent(s) despite no scanner"
      fi
      if [ "$(snap_get "$snap" verdict)" = "BLOCK" ]; then
        pass "$name: BLOCKed"
      else
        fail "$name: verdict was '$(snap_get "$snap" verdict)', expected BLOCK"
      fi ;;

    authoring-one-artifact)
      n="$(snap_get "$snap" files_written)"
      if [ "$n" = "1" ]; then
        pass "$name: wrote exactly one file"
      else
        fail "$name: wrote $n files, expected 1" "$(snap_get "$snap" written_paths)"
      fi
      if [ "$(snap_get "$snap" written_paths)" = "$(snap_get "$snap" expected_path)" ]; then
        pass "$name: at the expected §A4 path"
      else
        fail "$name: wrong path" \
             "got=$(snap_get "$snap" written_paths) want=$(snap_get "$snap" expected_path)"
      fi
      # Re-running must merge, never clobber (§A7).
      if [ "$(snap_get "$snap" preserved_existing)" != "no" ]; then
        pass "$name: preserved existing content"
      else
        fail "$name: clobbered existing content"
      fi ;;

    *)
      fail "$name: unknown contract '$contract'" "snapshot may be stale or hand-edited" ;;
  esac
done

echo ""
echo "$PASSED passed, $FAILED failed."
[ "$FAILED" -gt 0 ] && exit 1
exit 0
