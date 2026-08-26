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
case "$prompt" in
  *"capture this idea"*|*"capture the intent"*|*"write down the intent"*|*"before we plan"*)
    add "/capture-intent (record the raw idea as docs/intent/<slug>.md)" ;;
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
  *"full e2e"*|*"e2e gate"*|*"run and triage"*|*"release ready"*|*"ready to release"*)
    add "/e2e-suite (umbrella: run + triage + one verdict)" ;;
  *"test report"*|*traceability*|*"coverage against"*)
    add "/test-report (requirement → case → spec → defect)" ;;
  *"fix the test"*|*"repair the test"*|*"selector changed"*|*"broken spec"*)
    add "/test-repair (test-bug only; never weakens an assertion)" ;;
  # Wrapping-up phrasing. The standing rule is that a feature should ship with a
  # test, and this is the moment that rule applies — after the code is written and
  # before it leaves the machine.
  *"ship this"*|*"ready to push"*|*"done with the feature"*|*"finished the feature"*)
    add "/test-suite-author (a feature should ship with a test — ticket → specs)" ;;
  # Before /test-plan and /test-author: "write the tests for this ticket" wants the
  # whole chain, and both of those match it too. First match is the one that reads
  # as the answer.
  *"tests for this ticket"*|*"test suite for"*|*"ticket to specs"*|*"whole test suite"*)
    add "/test-suite-author (plan → specs → fixtures; pauses each stage)" ;;
  *"test plan"*|*"what should we test"*|*"test cases for"*)
    add "/test-plan (case matrix: boundaries, negative, authz)" ;;
  *"write the tests"*|*"generate spec"*|*"scaffold test"*|*"page object"*)
    add "/test-author (your framework; proposes the commit)" ;;
  *fixture*|*"test data"*|*"seed data"*|*"tests interfere"*)
    add "/test-data (per-spec data; credentials from env)" ;;
  *quarantin*|*"flaky test"*|*"flaky spec"*|*"which tests are flak"*)
    add "/flake-watch (ledger history; proposes quarantine, never applies)" ;;
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
  *"deep security"*|*"enterprise security"*|*"security audit"*|*"multi-agent security"*|*"multi agent security"*) add "/security-deep-review (multi-lens finders, adversarial verify)" ;;
esac
case "$prompt" in
  *bug*|*regression*|*correctness*|*"edge case"*) add "/review-correctness" ;;
esac

# Design parity — its own block, because "design" is both a noun ("match this
# design") and a verb ("design me a schema"), and one glob list cannot separate
# them. Order matters: unambiguous nouns, then the verb guard, then bare "design"
# only when a look-at-the-screen word is present.
#
# Widened after a run where 4 of the user's 7 complaints missed. The old pattern
# needed the literal "the design", so "old design", "new design" and the typo
# "desing" all slipped past — including "i dont see the design changes", the
# clearest possible call for this gate. Two phases shipped against the wrong
# mockup with the gate never suggested. check_hook_fires in check.sh pins these
# cases so the patterns cannot quietly narrow again.
case "$prompt" in
  # Nouns that never mean "invent something new".
  *mockup*|*figma*|*"claude design"*|*"claude-design"*|*"design system"*|*redesign*| \
  *"looks wrong"*|*"still see the old"*|*"does not match"*|*"doesn't match"*)
    add "/claude-design-pull (measure the page against the approved mockup)" ;;
  # design-as-a-VERB: an instruction to invent. Never this gate.
  *"design a "*|*"design an "*|*"design the "*|*"designing "*) ;;
  # Otherwise "design"/"desing" counts only beside a visual-state word.
  *design*|*desing*)
    case "$prompt" in
      *see*|*look*|*match*|*chang*|*old*|*new*|*same*|*slide*|*page*|*screen*|*ui*| \
      *layout*|*styl*|*theme*|*colou*|*color*|*font*|*pdf*|*screenshot*|*wrong*| \
      *apply*|*appli*|*land*|*pull*|*compar*|*parity*|*complet*|*done*)
        add "/claude-design-pull (measure the page against the approved mockup)" ;;
    esac ;;
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
#
# The second line is the one that matters in practice. Reporting a defect is the
# most common reason to want a tracked item, and it shares no vocabulary with
# "epic" or "user story" — a real miss looked like "MCP doesn't support X, it's a
# bug", which matched nothing here and got a hand-written issue instead of
# /pm-task. `issue` and `ticket` are the broad catches; the rest are the phrasings
# people actually reach for when something is wrong.
# NOTE these are shell GLOBS, not regexes: `*"break.*into"*` matched only the
# literal text "break.*into" and so never fired on "break this into stories".
# Use `*break*into*` — in a glob, `*` is the wildcard.
case "$prompt" in
  *break*into*|*epic*|*"user story"*|*"user stories"*|*backlog*|*plan*feature*)
    add "/pm-plan, /pm-epic, /pm-story, /pm-task" ;;
  *issue*|*ticket*|*"is a bug"*|*"its a bug"*|*"it's a bug"*|*"a defect"* \
    |*"file a"*|*"raise a"*|*"log a"*|*"track this"*|*"is broken"*)
    add "/pm-task, /pm-story (track it before writing code)" ;;
esac
# EM intelligence report
case "$prompt" in
  *newsletter*|*"vertical pulse"*|*"engagement manager"*|*"account intelligence"*|*"account deep-dive"*)
    add "/em-newsletter, /vertical-pulse" ;;
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
