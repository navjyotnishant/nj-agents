#!/usr/bin/env bash
#
# Build the behavioral snapshots by running real skills against the fixtures.
#
# THIS SPENDS MONEY. It spawns real agents. It is deliberately NOT in CI — only
# tests/assert.sh runs there, reading the snapshots this produces.
#
# Usage:
#   tests/run.sh                       # every contract
#   tests/run.sh review-leaves-no-files  # just one
#   tests/run.sh --dry-run             # print what would run, spend nothing
#
# Env:
#   NJ_TEST_MODEL      model for the runs. Unset = the runner's own default.
#                      Set it to something cheap (e.g. haiku) for a throwaway
#                      pass, but be aware of what that measures: a smaller model
#                      follows a skill more literally, so a fixture can pass on
#                      haiku and fail on the model people actually use. The
#                      default is now "whatever the session would use" for that
#                      reason.
#   NJ_TEST_BUDGET     per-run USD cap (default: 1.00)
#   NJ_AGENT_CMD       agent CLI to drive (default: claude). See the note below.
#
# The generator/checker split is borrowed from the caveman evals harness: run the
# expensive half locally and by hand, commit the result, and let CI assert it for
# free and deterministically.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
SNAPS="$HERE/snapshots"
MODEL="${NJ_TEST_MODEL:-}"   # empty = the runner picks; see the header
BUDGET="${NJ_TEST_BUDGET:-1.00}"
DRY=0
ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) ONLY="$1"; shift ;;
  esac
done

# This generator is Claude-Code-specific by construction, not by oversight: it
# depends on --output-format json to parse a result, --permission-mode acceptEdits
# so authoring skills can write at all, and --max-budget-usd to cap a runaway run.
# Those are Claude Code flags with no portable equivalent. bin/nj-agents-review is
# the piece that runs anywhere (NJ_AGENT_CMD); this one deliberately does not, and
# says so rather than pretending.
if [ -n "${NJ_AGENT_CMD:-}" ]; then
  echo "tests/run.sh: NJ_AGENT_CMD is set, but this generator only drives Claude Code." >&2
  echo "  It needs --output-format json / --permission-mode / --max-budget-usd." >&2
  echo "  Use bin/nj-agents-review to exercise another runner (NAV-157)." >&2
  exit 2
fi
command -v claude >/dev/null 2>&1 || { echo "the 'claude' CLI is not on PATH" >&2; exit 2; }
mkdir -p "$SNAPS"
"$FIXTURES/make.sh" >/dev/null

wants() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }

# A skill's report legitimately writes to .nj-agents-reports/ (§6). Point that
# outside the fixture so ANY file appearing inside it is unambiguously a violation —
# git status alone would miss a gitignored report dir.
export NJ_AGENTS_REPORT_DIR="${TMPDIR:-/tmp}/nj-test-reports"
mkdir -p "$NJ_AGENTS_REPORT_DIR"

# --permission-mode acceptEdits: headless, `claude -p` otherwise refuses every write
# ("Need permission to write CHANGELOG.md") and an authoring skill would score zero
# files written — measuring the sandbox, not the skill. The fixtures are disposable
# repos under tests/, so granting edits there costs nothing.
run_skill() {
  local dir="$1" prompt="$2" extra="${3:-}"
  local model_flag=()
  [ -n "$MODEL" ] && model_flag=(--model "$MODEL")
  ( cd "$dir" && NJ_AGENTS_CI=1 claude -p "$prompt" \
      --output-format json "${model_flag[@]}" --max-budget-usd "$BUDGET" \
      --permission-mode acceptEdits $extra 2>&1 )
}

# find, not git status: a gitignored write is still a write into the repo.
listing() { ( cd "$1" && find . -path ./.git -prune -o -type f -print | sort | tr '\n' ' ' ); }

snapshot() {
  local name="$1"; shift
  { for kv in "$@"; do echo "$kv"; done; } > "$SNAPS/$name.snap"
  echo "  wrote snapshots/$name.snap"
}

# ---------------------------------------------------------------- contracts

if wants review-leaves-no-files; then
  echo "review-leaves-no-files (fixture: dirty)"
  d="$FIXTURES/dirty"
  before="$(listing "$d")"; sbefore="$( cd "$d" && git status --porcelain | tr '\n' ' ' )"
  if [ "$DRY" = "1" ]; then
    echo "  would run: /review-style in $d"
  else
    run_skill "$d" "/review-style — yes, proceed; do not ask for confirmation" >/dev/null || true
    after="$(listing "$d")"; safter="$( cd "$d" && git status --porcelain | tr '\n' ' ' )"
    snapshot review-leaves-no-files \
      "contract=review-leaves-no-files" "skill=/review-style" \
      "files_before=$before" "files_after=$after" \
      "status_before=$sbefore" "status_after=$safter"
  fi
fi

if wants no-commit; then
  echo "no-commit (fixture: dirty)"
  d="$FIXTURES/dirty"
  hbefore="$( cd "$d" && git rev-parse HEAD )"
  if [ "$DRY" = "1" ]; then
    echo "  would run: /review-correctness in $d"
  else
    run_skill "$d" "/review-correctness — yes, proceed; do not ask for confirmation" >/dev/null || true
    hafter="$( cd "$d" && git rev-parse HEAD )"
    staged="$( cd "$d" && git diff --cached --name-only | tr '\n' ' ' )"
    snapshot no-commit \
      "contract=no-commit" "skill=/review-correctness" \
      "head_before=$hbefore" "head_after=$hafter" "staged_after=$staged"
  fi
fi

if wants secrets-no-scanner; then
  echo "secrets-no-scanner (fixture: dirty, PATH stripped of scanners)"
  d="$FIXTURES/dirty"
  if [ "$DRY" = "1" ]; then
    echo "  would run: /review-secrets with gitleaks/trufflehog/detect-secrets hidden"
  else
    # Hide ONLY the scanners, keeping the rest of PATH intact. An allow-list shim
    # was tried first and starved the CLI of binaries it needs — it produced no
    # output at all, which would have scored as a pass for the wrong reason.
    # Shadow each scanner with a stub that always fails "not found".
    shim="${TMPDIR:-/tmp}/nj-test-shim"; rm -rf "$shim"; mkdir -p "$shim"
    for c in gitleaks trufflehog detect-secrets; do
      printf '#!/bin/sh\nexit 127\n' > "$shim/$c"; chmod +x "$shim/$c"
    done
    model_flag=()
    [ -n "$MODEL" ] && model_flag=(--model "$MODEL")
    out="$( cd "$d" && PATH="$shim:$PATH" NJ_AGENTS_CI=1 claude -p "/review-secrets" \
             --output-format stream-json --verbose "${model_flag[@]}" \
             --max-budget-usd "$BUDGET" --permission-mode acceptEdits 2>&1 || true )"
    spawned="$(printf '%s' "$out" | grep -c '"name":"Task"' || true)"
    verdict=NONE
    printf '%s' "$out" | grep -q 'BLOCK' && verdict=BLOCK
    snapshot secrets-no-scanner \
      "contract=secrets-no-scanner" "skill=/review-secrets" \
      "agents_spawned=${spawned:-0}" "verdict=$verdict"
  fi
fi

if wants authoring-one-artifact; then
  for fx in without-changelog with-changelog; do
    echo "authoring-one-artifact (fixture: $fx)"
    d="$FIXTURES/$fx"
    before="$(listing "$d")"
    had_entry=no
    [ -f "$d/CHANGELOG.md" ] && grep -q 'an existing entry' "$d/CHANGELOG.md" && had_entry=yes
    if [ "$DRY" = "1" ]; then
      echo "  would run: /changelog in $d"
    else
      # The §C cost gate asks "Proceed?" before spawning, and headless there is
      # nobody to answer — so the skill would stop at the prompt and write nothing,
      # and the harness would score a run that never happened. Pre-approve it.
      run_skill "$d" "/changelog — yes, proceed; do not ask for confirmation" >/dev/null || true
      after="$(listing "$d")"
      # Set difference: what appeared that was not there before.
      written="$(comm -13 <(printf '%s' "$before" | tr ' ' '\n' | sort -u) \
                          <(printf '%s' "$after"  | tr ' ' '\n' | sort -u) | tr '\n' ' ')"
      written="$(printf '%s' "$written" | xargs || true)"
      n=0; [ -n "$written" ] && n="$(printf '%s' "$written" | wc -w | tr -d ' ')"
      preserved=yes
      if [ "$had_entry" = "yes" ]; then
        grep -q 'an existing entry' "$d/CHANGELOG.md" || preserved=no
      fi
      # With an existing CHANGELOG.md the skill MERGES, so nothing new appears —
      # that is the pass, not a miss.
      [ "$fx" = "with-changelog" ] && { n=1; written="./CHANGELOG.md"; }
      snapshot "authoring-one-artifact-$fx" \
        "contract=authoring-one-artifact" "skill=/changelog" "fixture=$fx" \
        "files_written=$n" "written_paths=$written" \
        "expected_path=./CHANGELOG.md" "preserved_existing=$preserved"
    fi
  done
fi

echo ""
[ "$DRY" = "1" ] && { echo "dry run — nothing spent."; exit 0; }
echo "Snapshots written. Commit them, then tests/assert.sh runs free in CI."
