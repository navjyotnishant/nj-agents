#!/usr/bin/env bash
# UserPromptSubmit hook: surface the matching nj-agents skill for a prompt.
#
# Why this exists: the global CLAUDE.md already says "prefer the matching skill
# over improvising the same task by hand" — but that relies on the model
# remembering, and in a long build/test/PR loop it silently stops happening.
# This makes the reminder mechanical.
#
# It only ADDS context. It never blocks a prompt and never runs a skill.
set -euo pipefail

# jq is detected, never required (CONVENTIONS-authoring.md §A5). Without this guard
# `set -euo pipefail` would fail the hook on EVERY prompt on a machine that lacks it
# — a suggestion helper must never be the reason a prompt breaks.
command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat)
prompt=$(printf '%s' "$payload" | jq -r '.prompt // ""' 2>/dev/null | tr '[:upper:]' '[:lower:]')
[ -z "$prompt" ] && exit 0

matches=""
add() { case "$matches" in *"$1"*) ;; *) matches="${matches}${matches:+, }$1" ;; esac; }

# push / ship / release -> review gate first
case "$prompt" in
  *push*|*ship*|*"pull request"*|*" pr "*|*merge*)
    add "/pre-push-review (review the diff before pushing)"
    add "/pr-describe (draft the PR title + body)" ;;
esac
case "$prompt" in
  *commit*) add "/commit-assistant (draft Conventional Commit messages)" ;;
esac
case "$prompt" in
  *changelog*|*"release notes"*|*"cut a release"*|*"release "*)
    add "/changelog and /release-notes" ;;
esac
# docs / explaining the system
case "$prompt" in
  *document*|*documentation*|*docs*|*readme*|*guide*|*"write up"*)
    add "/docs-site (browsable docs page)" ;;
esac
case "$prompt" in
  *diagram*|*architecture*|*"how does"*"fit together"*|*"where.*live"*|*flow*)
    add "/arch-diagram (real diagram, render->QA loop)" ;;
esac
# repo maintenance
case "$prompt" in
  *"dead code"*|*unused*) add "/dead-code-finder" ;;
esac
case "$prompt" in
  *"test gap"*|*coverage*|*untested*) add "/test-gap-finder" ;;
esac
case "$prompt" in
  *upgrade*|*outdated*|*dependenc*) add "/deps-upgrade or /review-dependencies" ;;
esac
case "$prompt" in
  # Triage first: "why did the e2e tests fail" is a triage question, not a run one.
  *"why did"*test*fail*|*"why are"*test*fail*|*triage*|*"real bug or"*|*flake*)
    add "/test-triage (defect · test-bug · env · flake · data, with evidence)" ;;
  *"e2e"*|*"end-to-end"*|*"browser test"*|*"playwright"*|*"cypress"*)
    add "/e2e-run (detects your runner; BLOCKs on a prod URL)" ;;
esac
case "$prompt" in
  # Order matters: "refresh the screenshots in the docs" is the sync case, not a
  # one-shot capture, and the first match is the one that reads as the answer.
  *"docs"*screenshot*|*screenshot*"docs"*|*"refresh the docs"*|*"sync the docs"*)
    add "/screenshot-docs-sync (re-captures only what changed)" ;;
  *screenshot*) add "/capture-screenshots (auto-redacts PII)" ;;
esac
case "$prompt" in
  *"blog"*|*article*) add "/tech-blog" ;;
esac
case "$prompt" in
  *"new repo"*|*scaffold*|*bootstrap*) add "/scaffold-project" ;;
esac
# The individual review dimensions, for when the whole umbrella is more than asked.
case "$prompt" in
  *secret*|*credential*|*token*|*"api key"*) add "/review-secrets (scanner gate, then a semantic pass)" ;;
esac
case "$prompt" in
  *bug*|*regression*|*correctness*|*"edge case"*) add "/review-correctness" ;;
esac
case "$prompt" in
  *lint*|*"run the tests"*|*build*) add "/review-tests-build" ;;
esac
case "$prompt" in
  *style*|*convention*|*formatting*) add "/review-style" ;;
esac
case "$prompt" in
  *linkedin*|*twitter*|*" x "*|*social*|*promote*) add "/social-post" ;;
esac
# planning / tracker
case "$prompt" in
  *"break.*into"*|*epic*|*"user story"*|*backlog*|*"plan.*feature"*)
    add "/pm-plan, /pm-epic, /pm-story, /pm-task" ;;
esac

[ -z "$matches" ] && exit 0

jq -nc --arg m "$matches" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: ("Installed nj-agents skills that may match this request: " + $m +
      ". Per the global CLAUDE.md, prefer the matching skill over doing the task by hand — " +
      "offer it to the user (do not fire it unprompted). If none genuinely fits, ignore this.")
  }
}'
