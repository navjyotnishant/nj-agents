#!/usr/bin/env bash
#
# nj-agents validator — checks that the skills and agents in this repo are
# structurally sound, reference each other correctly, and honour the contract
# of the class they declare.
#
# Usage:
#   ./check.sh                   # run every check; report findings, exit 0 (advisory)
#   ./check.sh --strict          # same, but exit 1 if anything was found (CI)
#   ./check.sh --json            # machine-readable findings on stdout
#
#   ./check.sh --new-skill NAME --class review|authoring|workflow|pm|social|testing
#   ./check.sh --new-agent NAME
#                                # scaffold from templates/, then validate it
#
# It GLOBS skills/*/ and agents/*.md rather than reading a list, so a skill added
# tomorrow is covered the moment its directory exists — there is no registration
# step to forget. Advisory by default so it can never break an install; --strict
# is what makes it a gate.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_DIR/skills"
AGENTS_SRC="$REPO_DIR/agents"
GLOBAL_MD_SRC="$REPO_DIR/global/AGENTS.md"
REPO_MD_SRC="$REPO_DIR/CLAUDE.md"
STRICT=0
JSON=0
FINDINGS=0
JSON_ROWS=""

NEW_SKILL=""
NEW_AGENT=""
NEW_CLASS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --json) JSON=1; shift ;;
    --new-skill) NEW_SKILL="$2"; shift 2 ;;
    --new-agent) NEW_AGENT="$2"; shift 2 ;;
    --class) NEW_CLASS="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Scaffolding, so the compliant path is also the easiest one. A validator alone is a
# wall; this is the door. The new file is deliberately NOT complete — it is a correct
# skeleton with the required sections marked, and the validator runs immediately
# afterwards so the author sees what is still missing now rather than at review time.
scaffold() {
  local kind="$1" name="$2" class="${3:-}" tmpl dst
  case "$name" in
    ''|*[!a-z0-9-]*) echo "  ! '$name' must be kebab-case (a-z, 0-9, -)" >&2; exit 2 ;;
  esac
  if [ "$kind" = "skill" ]; then
    case "$class" in
      review|authoring|workflow|pm|social|testing) ;;
      *) echo "  ! --class must be one of: review authoring workflow pm social testing" >&2; exit 2 ;;
    esac
    tmpl="$REPO_DIR/templates/SKILL.md"; dst="$SKILLS_SRC/$name/SKILL.md"
  else
    tmpl="$REPO_DIR/templates/agent.md"; dst="$AGENTS_SRC/$name.md"
  fi
  [ -f "$tmpl" ] || { echo "  ! missing template: ${tmpl#$REPO_DIR/}" >&2; exit 2; }
  [ -e "$dst" ] && { echo "  ! ${dst#$REPO_DIR/} already exists — refusing to overwrite" >&2; exit 2; }

  mkdir -p "$(dirname "$dst")"
  # author comes from git config, never hardcoded — a teammate's file records them.
  local who; who="$(git config user.name 2>/dev/null || true)"
  [ -n "$who" ] || { echo "  ! git config user.name is unset — set it so authorship is recorded" >&2; exit 2; }
  sed -e "s/SKILL_NAME/$name/g" -e "s/AGENT_NAME/$name/g" -e "s/SKILL_CLASS/$class/g" \
      -e "s/AUTHOR_NAME/$who/g" "$tmpl" > "$dst"
  # A review skill must pick gate or scan; seed the key so the author sees the choice.
  [ "$class" = "review" ] && sed -i.bak '/^class: review$/a\
subclass: gate
' "$dst" && rm -f "$dst.bak"
  echo "  created ${dst#$REPO_DIR/}"
  echo "  fill the ALL-CAPS placeholders and the sections marked REQUIRED, then re-run ./check.sh"
  echo ""
}

if [ -n "$NEW_SKILL" ] || [ -n "$NEW_AGENT" ]; then
  [ -n "$NEW_SKILL" ] && scaffold skill "$NEW_SKILL" "$NEW_CLASS"
  [ -n "$NEW_AGENT" ] && scaffold agent "$NEW_AGENT"
  echo "Validating ..."
fi

# Every finding funnels through here: counts it, and either prints it or stashes
# it for the --json report. `kind` is structural | referential | doc-sync, the
# same who-fixes-this split qa_diagram.js uses for diagram issues.
finding() {
  local check="$1" kind="$2" detail="$3"
  FINDINGS=$((FINDINGS + 1))
  if [ "$JSON" = "1" ]; then
    detail="${detail//\\/\\\\}"; detail="${detail//\"/\\\"}"
    JSON_ROWS="$JSON_ROWS{\"check\":\"$check\",\"kind\":\"$kind\",\"detail\":\"$detail\"},"
  else
    echo "  ! $detail" >&2
  fi
}

ok() { [ "$JSON" = "1" ] || echo "  $1"; }

# Content checks must read what the skill SAYS, not the scaffolding that tells an
# author what to write. A template's guidance comments legitimately name the very
# tokens the checks look for ("a gate must define its BLOCK verdict"), so matching
# raw text would let a freshly-scaffolded skill pass on boilerplate alone — a false
# negative in exactly the checks that matter most. Strip HTML comments first.
# awk keeps this dependency-free — no perl, no python, nothing a bare CI runner
# might lack. Comment markers in these files always sit on their own lines, so a
# line-oriented strip is sufficient.
body() {
  awk '/<!--/{skip=1} !skip{print} /-->/{skip=0}' "$1"
}

# `body "$f" | grep -q X` is a trap: grep -q exits at the first match and closes the
# pipe, body dies of SIGPIPE, and under `set -euo pipefail` that intermittently takes
# the whole check with it — findings varied run to run. Capture first, then match.
has() {
  local txt; txt="$(body "$1")"
  printf '%s' "$txt" | grep -q${3:-} -- "$2"
}

# A skill may declare `self_contained: true` in frontmatter when it deliberately
# carries its whole method inline so it runs on any agentic platform (e.g.
# em-newsletter/vertical-pulse) rather than leaning on this repo's shared
# CONVENTIONS. Such a skill is EXEMPT from the citation checks — cites-a-conventions
# -file, the readlink block, §A3/§A4, §U, and internal §N section validation — because
# those rules assume the skill reads files that ship only with this toolkit. It is NOT
# exempt from frontmatter validity, naming, cost/progress, or any other structural
# rule. The marker is the whole opt-out: no hardcoded skill list (§ the same trap the
# spawn-detection comment calls out).
is_self_contained() { grep -qm1 '^self_contained: *true' "$1"; }

# Frontmatter is the one thing every skill must get right — it is what makes the
# skill loadable at all. name must equal the directory so a rename can't leave a
# skill answering to a stale name; class is what every class-conditional check
# below keys off, so a missing one silently exempts the skill from its own rules.
check_skill_frontmatter() {
  local d name key val bad=0
  for d in "$SKILLS_SRC"/*/; do
    name="$(basename "${d%/}")"
    if [ ! -f "${d%/}/SKILL.md" ]; then
      finding check_skill_frontmatter structural "skills/$name/ has no SKILL.md"
      bad=1; continue
    fi
    for key in name description version class; do
      grep -q "^$key:" "${d%/}/SKILL.md" || {
        finding check_skill_frontmatter structural "skills/$name: frontmatter missing '$key:'"
        bad=1
      }
    done
    val="$(grep -m1 '^name:' "${d%/}/SKILL.md" | sed 's/^name: *//' || true)"
    [ "$val" = "$name" ] || {
      finding check_skill_frontmatter structural "skills/$name: name: is '$val', must match the directory"
      bad=1
    }
    val="$(grep -m1 '^version:' "${d%/}/SKILL.md" | sed 's/^version: *//' || true)"
    case "$val" in
      [0-9]*.[0-9]*.[0-9]*) ;;
      *) finding check_skill_frontmatter structural "skills/$name: version '$val' is not semver"; bad=1 ;;
    esac
    val="$(grep -m1 '^class:' "${d%/}/SKILL.md" | sed 's/^class: *//' || true)"
    case "$val" in
      review|authoring|workflow|pm|social|testing|"") ;;
      *) finding check_skill_frontmatter structural "skills/$name: unknown class '$val'"; bad=1 ;;
    esac
  done
  [ "$bad" = "0" ] && ok "skill frontmatter ok ($(ls -d "$SKILLS_SRC"/*/ | wc -l | tr -d ' ') skills)"
  return 0
}

# Frontmatter must be VALID YAML, not merely parseable by a lenient reader. An
# unquoted scalar containing ": " is a mapping-value error: YAML reads it as a
# nested key. Claude Code and Gemini shrug and load the skill anyway; Codex refuses
# it outright —
#   ERROR failed to load skill .../commit-assistant/SKILL.md: invalid YAML:
#   mapping values are not allowed in this context
# — which is how "It NEVER runs git itself: the human decides" silently made two
# skills invisible on one runner. Quote the value and it is fine everywhere.
# Model- and runner-agnosticism has to be ENFORCED, not just described, or it lasts
# exactly as long as the next author who has not read the template. Three ways it
# rots, all silent — nothing errors, the toolkit just quietly stops being portable:
#
#   1. `model:` in an agent — pins a tier and overrides the user's own choice. An
#      Opus session silently gets Sonnet subagents (this was NAV-146).
#   2. A vendor name in a user-facing banner — the privacy claim stays true, but it
#      names a product that is not running (NAV-150).
#   3. A model name in prose — "run this on haiku" is a recommendation that cannot
#      be honoured off one vendor.
#
# The agent case is a hard failure. The prose cases are matched narrowly, since a
# skill may legitimately *discuss* a runner: `check_frontmatter_yaml`'s comment
# names Codex, and CLAUDE.md/AGENTS.md are real files skills read as input.
check_vendor_neutral() {
  local f name val bad=0 txt
  for f in "$AGENTS_SRC"/*.md; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .md)"
    if grep -q '^model:' "$f"; then
      val="$(grep -m1 '^model:' "$f" | sed 's/^model: *//')"
      finding check_vendor_neutral structural \
        "agents/$name.md pins 'model: $val' — omit it so the agent inherits the session's model, or an Opus session silently gets $val subagents"
      bad=1
    fi
  done

  # Banners are what the USER reads, so a vendor name there is a false statement
  # about what is running. Skill bodies only; agent bodies are model-facing.
  for f in "$SKILLS_SRC"/*/SKILL.md; do
    [ -f "$f" ] || continue
    name="$(basename "$(dirname "$f")")"
    txt="$(body "$f")"
    if printf '%s' "$txt" | grep -qiE '(this|the current) (claude|codex|cursor|gemini) session'; then
      finding check_vendor_neutral structural \
        "skills/$name names a specific vendor in a user-facing claim ('this <vendor> session') — say 'this session', which is true on every runner"
      bad=1
    fi
    # A bare model name recommended for a run. Anchored on the recommendation, not
    # the word: a skill may name a model when explaining what it does NOT assume.
    if printf '%s' "$txt" | grep -qiE '(run|use|default)[a-z]* (it |this |them )?(on|with) (haiku|sonnet|opus|gpt-[0-9]|gemini-[0-9])'; then
      finding check_vendor_neutral structural \
        "skills/$name recommends a specific model — the session picks the model, not the skill"
      bad=1
    fi
  done

  [ "$bad" = "0" ] && ok "no pinned models, no vendor names in user-facing claims"
  return 0
}

check_frontmatter_yaml() {
  local f name key val bad=0
  for f in "$SKILLS_SRC"/*/SKILL.md "$AGENTS_SRC"/*.md; do
    [ -f "$f" ] || continue
    case "$f" in
      "$SKILLS_SRC"/*) name="skills/$(basename "$(dirname "$f")")" ;;
      *)               name="agents/$(basename "$f")" ;;
    esac
    # Frontmatter only: everything between the first two --- lines.
    while IFS= read -r line; do
      case "$line" in
        [a-z_]*": "*) ;;
        *) continue ;;
      esac
      key="${line%%: *}"
      val="${line#*: }"
      case "$val" in
        '"'*|"'"*) continue ;;   # quoted — a colon inside is safe
      esac
      case "$val" in
        *": "*)
          finding check_frontmatter_yaml structural \
            "$name: '$key:' is an unquoted value containing ': ' — invalid YAML, and Codex refuses to load it. Wrap the value in double quotes."
          bad=1 ;;
      esac
    done < <(awk '/^---$/{n++; next} n==1' "$f")
  done
  [ "$bad" = "0" ] && ok "frontmatter is valid YAML on every runner"
  return 0
}

check_agent_frontmatter() {
  local f name key val bad=0
  for f in "$AGENTS_SRC"/*.md; do
    name="$(basename "$f" .md)"
    # No `model:` — an agent inherits the session's model, so an Opus session gets
    # Opus subagents. Pinning one in the file silently overrides the user's choice.
    # If an agent ever needs a specific tier, it states why in its own body.
    #
    # `tools:` IS required, and the reason is portability rather than taste. Claude
    # Code and Cursor read a missing key as inherit-all, but Gemini CLI reads it as
    # *no tools* — the agent loads and then cannot do anything. An explicit list is
    # the only spelling that means the same thing on every runner.
    for key in name description tools color; do
      grep -q "^$key:" "$f" || {
        finding check_agent_frontmatter structural "agents/$name.md: frontmatter missing '$key:'"
        bad=1
      }
    done
    val="$(grep -m1 '^name:' "$f" | sed 's/^name: *//' || true)"
    [ "$val" = "$name" ] || {
      finding check_agent_frontmatter structural "agents/$name.md: name: is '$val', must match the filename"
      bad=1
    }

    # An agent whose own body says it is read-only must not hand itself a write
    # tool. The prose and the tool list are two statements of the same contract,
    # and a silent disagreement between them is exactly how an advise-only
    # reviewer starts editing the repo it was asked to review.
    val="$(grep -m1 '^tools:' "$f" | sed 's/^tools: *//' || true)"
    if printf '%s' "$val" | grep -qE '\b(Write|Edit|NotebookEdit)\b'; then
      # Anchor on the agent's own safety posture, not any mention of the words.
      # "only safe, read-only/demo commands" describes what an agent may RUN and
      # says nothing about whether it writes — matching it flagged an agent whose
      # whole job is producing an image file.
      if body "$f" | grep -qiE '^(Read-only\b|Do not write files|Never write files)'; then
        finding check_agent_frontmatter contract \
          "agents/$name.md: declares a write tool but its body says it is read-only"
        bad=1
      fi
    fi
  done
  [ "$bad" = "0" ] && ok "agent frontmatter ok ($(ls "$AGENTS_SRC"/*.md | wc -l | tr -d ' ') agents)"
  return 0
}

# Provenance has to live in the file. Skills install as SYMLINKS into ~/.claude/ and
# are invoked from any repo on the machine — at the point of use there is no git
# history to consult, so the file is the only record of where it came from.
check_authorship() {
  local f name bad=0
  for f in "$SKILLS_SRC"/*/SKILL.md "$AGENTS_SRC"/*.md; do
    [ -f "$f" ] || continue
    name="${f#$REPO_DIR/}"
    grep -q '^author:' "$f" || {
      finding check_authorship structural "$name declares no 'author:'"
      bad=1
    }
  done
  [ "$bad" = "0" ] && ok "authorship declared"
  return 0
}

# Two directions, two different bugs. A DANGLING reference means a skill tries to
# spawn an agent that isn't there — it fails at runtime, in whatever repo the user
# happened to be in. An ORPHAN means an agent nothing spawns: dead weight that
# still ships, and usually the sign a skill quietly stopped delegating.
check_agent_references() {
  local f name refs r s flat bad=0
  for f in "$SKILLS_SRC"/*/SKILL.md; do
    name="$(basename "$(dirname "$f")")"
    # `|| true`: a skill with no backticked tokens is fine, but grep exits 1 on
    # no-match and `set -e` would take the whole script down with it.
    refs="$(grep -o '`[a-z0-9-]\{3,\}`' "$f" 2>/dev/null | tr -d '`' | sort -u || true)"
    for r in $refs; do
      case "$r" in
        *-reviewer|*-writer|*-checker|*-architect|*-designer|*-capturer|*-redactor|\
        *-runner|*-finder|*-decomposer|*-describer|*-qa|*-editor|*-polish|\
        *-lint|*-poster|*-upgrade|*-post)
          [ -f "$AGENTS_SRC/$r.md" ] || {
            finding check_agent_references referential "skills/$name references agent '$r' — no agents/$r.md"
            bad=1
          } ;;
      esac
    done
  done
  # Every SKILL.md with newlines flattened to spaces, so a dispatch that wraps
  # across a line ("spawn the\n`tests-build-runner` agent") is still one match.
  # Built once rather than per-agent.
  flat="$(for s in "$SKILLS_SRC"/*/SKILL.md; do tr '\n' ' ' < "$s"; echo; done)"

  # An orphan is an agent NOTHING SPAWNS — so look for a spawn, not a mention.
  # A bare `grep -F "\`name\`"` is fooled by the four agents whose name matches a
  # skill (dead-code-finder, deps-upgrade, test-gap-finder, social-post): the
  # skill's own prose says `/deps-upgrade` and `deps-upgrade` constantly, so the
  # agent looks referenced even if its spawn line is deleted. Verified: removing
  # the only Spawn line from deps-upgrade left check.sh reporting no orphans.
  for f in "$AGENTS_SRC"/*.md; do
    name="$(basename "$f" .md)"
    # Dispatch is written several ways across the suite, and some of them wrap
    # across a line ("spawn the\n`tests-build-runner` agent"), so flatten the
    # whitespace first and match the phrasings that actually occur:
    #   Spawn `x` · spawn the `x` agent · run in parallel: `a`, `b` · the `x` agent
    # A slash-command reference (`/deps-upgrade`) is deliberately NOT a match.
    # NOT `printf | grep -q`: grep -q exits at the first match and closes the pipe,
    # printf dies of SIGPIPE, and under `set -euo pipefail` the whole match reads as
    # a failure — the same trap `has()` documents above. Count instead of -q.
    [ "$(printf '%s' "$flat" | grep -ciE \
      "(spawn|launch|dispatch)[a-z]*( +the)? +\`$name\`|\`$name\` +agent|\`$name\`[,)] *(and)? *\`" || true)" != "0" ] || {
      finding check_agent_references referential \
        "agents/$name.md is an orphan — no SKILL.md spawns it (a mention is not a spawn)"
      bad=1
    }
  done
  [ "$bad" = "0" ] && ok "agent references resolve (no dangling, no orphans)"
  return 0
}

# The class a skill declares determines which shared rules apply to it, so a
# declared class that cites the wrong conventions file — or cites none — means the
# skill is running under rules nobody wrote down.
check_class_conventions() {
  local d name class want bad=0
  for d in "$SKILLS_SRC"/*/; do
    name="$(basename "${d%/}")"
    [ -f "${d%/}/SKILL.md" ] || continue
    is_self_contained "${d%/}/SKILL.md" && continue
    class="$(grep -m1 '^class:' "${d%/}/SKILL.md" | sed 's/^class: *//' || true)"
    [ -n "$class" ] || continue
    # Workflow class "sits between review and authoring" (CLAUDE.md): it borrows
    # §A3/§A5 from authoring and diff-reading from review, so either file is a
    # legitimate citation. Don't force one.
    case "$class" in
      authoring|social) want="CONVENTIONS-authoring.md" ;;
      pm)               want="CONVENTIONS-pm.md" ;;
      review)           want="CONVENTIONS.md" ;;
      workflow)         want="" ;;
      *) continue ;;
    esac
    grep -q 'CONVENTIONS[a-z-]*\.md' "${d%/}/SKILL.md" || {
      finding check_class_conventions referential "skills/$name (class: $class) cites no conventions file at all"
      bad=1; continue
    }
    [ -z "$want" ] && continue
    grep -q "$want" "${d%/}/SKILL.md" || {
      finding check_class_conventions referential "skills/$name declares class: $class but never cites $want"
      bad=1
    }
  done
  [ "$bad" = "0" ] && ok "class ↔ conventions agree"
  return 0
}

# Moved here from install.sh, and inverted: it used to fire only if a skill
# happened to mention a conventions file, which made it opt-in by accident.
# Skills install as symlinks into ~/.claude/skills/, so a plain relative path
# resolves against the LINK and misses the file — the skill then runs without its
# shared rules and nothing says why.
check_conventions_reachable() {
  local f name bad=0
  for f in "$SKILLS_SRC"/*/SKILL.md; do
    name="$(basename "$(dirname "$f")")"
    is_self_contained "$f" && continue
    grep -q 'readlink -f' "$f" || {
      finding check_conventions_reachable referential \
        "skills/$name has no 'Finding the conventions file' block (needs the readlink -f note)"
      bad=1
    }
  done
  [ "$bad" = "0" ] && ok "conventions references resolvable"
  return 0
}

# THE one that matters. Every other check here catches a typo; this catches a
# skill that looks fine but quietly opted out of its class's safety rails — a
# review skill with no CI mode, an authoring skill that never proposes the commit.
# That is the silent-failure mode this whole validator exists to close.
#
# Review skills may DELEGATE the shared rules ("follow CONVENTIONS.md §5") instead
# of restating them; that is the intended design, so citing the section counts.
#
# The class splits in two: a `gate` reviews a DIFF and answers "is this safe to
# push?" (PASS/WARN/BLOCK, honoured by a hook), while a `scan` sweeps the WHOLE
# repo for accumulated debt and returns candidates — there is no sensible BLOCK
# for "you have 12 unused exports". Only gates are held to the verdict tokens.
# That split is read from `subclass:`, never from a list of skill names here: a
# hardcoded allowlist would silently exempt skill #24, which is the exact
# forget-to-update failure this validator exists to catch.
check_class_contract() {
  local d name class f sub bad=0
  for d in "$SKILLS_SRC"/*/; do
    name="$(basename "${d%/}")"; f="${d%/}/SKILL.md"
    [ -f "$f" ] || continue
    is_self_contained "$f" && continue
    class="$(grep -m1 '^class:' "$f" | sed 's/^class: *//' || true)"
    case "$class" in
      review)
        has "$f" 'NJ_AGENTS_CI\|CONVENTIONS\.md §5\|§5' || {
          finding check_class_contract referential \
            "skills/$name (review) defines no CI mode — needs NJ_AGENTS_CI or a CONVENTIONS.md §5 reference"
          bad=1
        }
        sub="$(grep -m1 '^subclass:' "$f" | sed 's/^subclass: *//' || true)"
        case "$sub" in
          gate)
            has "$f" 'BLOCK' || {
              finding check_class_contract referential \
                "skills/$name (review/gate) never mentions a BLOCK verdict"
              bad=1
            } ;;
          scan) ;;
          "")
            finding check_class_contract structural \
              "skills/$name (review) declares no 'subclass:' — must be gate (reviews a diff) or scan (sweeps the repo)"
            bad=1 ;;
          *)
            finding check_class_contract structural \
              "skills/$name: unknown subclass '$sub' — expected gate or scan"
            bad=1 ;;
        esac ;;
      authoring)
        has "$f" '§A3' || {
          finding check_class_contract referential \
            "skills/$name (authoring) never cites §A3 — must propose the commit, never run git"
          bad=1
        }
        has "$f" '§A4' || {
          finding check_class_contract referential \
            "skills/$name (authoring) never cites §A4 — must name where its artifact lands"
          bad=1
        } ;;
      pm)
        has "$f" '§P2' || {
          finding check_class_contract referential \
            "skills/$name (pm) never cites §P2 — must use the neutral issue model"
          bad=1
        }
        has "$f" 'paste-ready\|markdown fallback' i || {
          finding check_class_contract referential \
            "skills/$name (pm) has no paste-ready-markdown fallback (§P3/§P6)"
          bad=1
        } ;;
      testing)
        # This class writes source AND executes it against a running app — the only
        # class that does either. T1/T2/T3 are what keep that safe, so they are
        # asserted rather than left to prose (which is how `social` ended up with no
        # enforced contract at all).
        #
        # A read-only testing skill (/test-plan, /test-report) has nothing to fence,
        # so it opts out by SAYING it is read-only — never by omission, or the
        # exemption becomes the default.
        if ! has "$f" 'read-only\|writes nothing\|never writes' i; then
          has "$f" 'test director\|only .*test dir\|§T1\|T1 ' i || {
            finding check_class_contract referential \
              "skills/$name (testing) never states the T1 source fence — writes only inside detected test directories, never app source"
            bad=1
          }
        fi
        # T2 binds anything that edits an existing spec. "Green by deletion" is the
        # failure mode, and it is invisible in a passing suite.
        #
        # A skill that DENIES repairing ("never repairs anything") or merely points
        # at /test-repair is not bound by T2 — it is asserting the opposite. The
        # umbrella tripped this on its own disclaimer, which would have taught the
        # next author to satisfy the check by pasting T2 language into a skill that
        # does not repair. A rule that rewards noise is worse than no rule.
        if has "$f" 'repair\|fix the test\|edit.*spec' i \
           && ! has "$f" 'never repairs\|does not repair\|repairs nothing\|no repair path' i; then
          has "$f" 'weaken\|delete an assertion\|§T2\|T2 ' i || {
            finding check_class_contract referential \
              "skills/$name (testing) edits specs but never states T2 — may not weaken or delete an assertion, add a sleep, raise retries, or add a skip"
            bad=1
          }
        fi
        # T3 is the one clause whose blast radius is outside the repo.
        if has "$f" 'base url\|run the suite\|execute' i; then
          has "$f" 'non-prod\|§T3\|T3 ' i || {
            finding check_class_contract referential \
              "skills/$name (testing) runs against an app but never states the T3 non-prod gate"
            bad=1
          }
        fi ;;
      workflow)
        # A workflow skill must never push or tag — that half is absolute. Running
        # `git commit` is allowed, but ONLY behind an explicit per-item approval:
        # §U forbids acting on the skill's own initiative, not acting on a yes.
        # So require both halves, or a skill could satisfy this by saying "never
        # pushes" while committing silently.
        has "$f" 'never push\|never .*push\|does not push\|stops at the commit' i || {
          finding check_class_contract referential \
            "skills/$name (workflow) never states that it does not push"
          bad=1
        }
        if has "$f" 'git commit' i && ! has "$f" 'never runs? git\|print blocks only\|never execute' i; then
          has "$f" 'ask.*per commit\|per commit\|explicit.*yes\|go-ahead\|opt-in\|only on.*approval' i || {
            finding check_class_contract referential \
              "skills/$name (workflow) may run git commit but names no approval gate — §U allows it only on an explicit go-ahead"
            bad=1
          }
        fi ;;
    esac
  done
  [ "$bad" = "0" ] && ok "class contracts honoured"
  return 0
}

# A skill that spawns agents spends the user's money and, while it runs, is a black
# box. Both checks below key off SPAWN DETECTION rather than a list of skill names:
# a hardcoded list would silently exempt skill #24, which is the same failure this
# validator exists to catch.
spawns_agents() { body "$1" | grep -qi 'spawn'; }

# §U binds every skill regardless of class. Restating universal rules per class is
# what let them drift — "no secrets" landed in two conventions docs and "ground
# everything" in one, so a PM skill was never formally bound by grounding at all.
check_universal_rules() {
  local d name bad=0
  for d in "$SKILLS_SRC"/*/; do
    name="$(basename "${d%/}")"
    [ -f "${d%/}/SKILL.md" ] || continue
    is_self_contained "${d%/}/SKILL.md" && continue
    has "${d%/}/SKILL.md" '§U' || {
      finding check_universal_rules referential \
        "skills/$name never cites §U — the rules that bind every skill (grounding, no secrets, human commits, changelog)"
      bad=1
    }
  done
  [ "$bad" = "0" ] && ok "universal rules cited"
  return 0
}

# A skill that shells out to something must say so where a reader can SEE it, before
# running it — not bury it in prose and not let them find out from an error. Keyed off
# the tools actually named in the skill, never a list of skill names.
check_dependencies() {
  local d name bad=0 tools
  tools='gitleaks\|trufflehog\|detect-secrets\|rsvg-convert\|playwright\|`sharp`\|`jimp`\|`gh`\|mkdocs\|`npx`'
  for d in "$SKILLS_SRC"/*/; do
    name="$(basename "${d%/}")"
    [ -f "${d%/}/SKILL.md" ] || continue
    has "${d%/}/SKILL.md" "$tools" || continue
    grep -q '^## Dependencies' "${d%/}/SKILL.md" || {
      finding check_dependencies referential \
        "skills/$name names an external tool but has no '## Dependencies' table (what it needs, and what happens without it)"
      bad=1
    }
  done
  [ "$bad" = "0" ] && ok "external dependencies documented"
  return 0
}

# §C — the user should never discover the cost mid-run.
check_cost_control() {
  local f name bad=0
  for f in "$SKILLS_SRC"/*/SKILL.md; do
    name="$(basename "$(dirname "$f")")"
    spawns_agents "$f" || continue
    has "$f" 'CONVENTIONS-orchestration\.md\|§C' || {
      finding check_cost_control referential \
        "skills/$name spawns agents but never cites the cost rules (CONVENTIONS-orchestration.md §C)"
      bad=1
    }
    has "$f" 'cost shape' i || {
      finding check_cost_control referential \
        "skills/$name spawns agents but states no cost shape (how many agents / what loop)"
      bad=1
    }
  done
  [ "$bad" = "0" ] && ok "spawning skills declare their cost"
  return 0
}

# §R — a subagent cannot report mid-run, so the spawning skill must.
check_progress_reporting() {
  local f name bad=0
  for f in "$SKILLS_SRC"/*/SKILL.md; do
    name="$(basename "$(dirname "$f")")"
    spawns_agents "$f" || continue
    has "$f" '§R' || {
      finding check_progress_reporting referential \
        "skills/$name spawns agents but never cites the progress-reporting rules (§R)"
      bad=1
    }
    has "$f" 'roster\|announce' i || {
      finding check_progress_reporting referential \
        "skills/$name spawns agents but never announces what it dispatched"
      bad=1
    }
  done
  [ "$bad" = "0" ] && ok "spawning skills report their progress"
  return 0
}

# A skill citing "§A9" that does not exist reads as authoritative and is not.
# Catches the drift in the direction install.sh never looked: the citation is
# fine today, then someone renumbers the conventions file.
check_conventions_sections() {
  local f sec num doc bad=0
  for f in "$SKILLS_SRC"/*/SKILL.md "$AGENTS_SRC"/*.md; do
    # A self-contained skill numbers its OWN sections (§9, §11 …); those are internal
    # cross-references, not citations of a CONVENTIONS doc — don't validate them here.
    case "$f" in "$SKILLS_SRC"/*/SKILL.md) is_self_contained "$f" && continue ;; esac
    for sec in $(grep -o '§[APTU]\{0,1\}[0-9]\{1,2\}' "$f" 2>/dev/null | sort -u); do
      num="${sec#§}"
      case "$num" in
        A*) doc="CONVENTIONS-authoring.md" ;;
        P*) doc="CONVENTIONS-pm.md" ;;
        T*) doc="CONVENTIONS-testing.md" ;;
        *)  doc="CONVENTIONS.md" ;;
      esac
      grep -q "^## §\{0,1\}$num[. ]\|^## $num\." "$REPO_DIR/$doc" || {
        finding check_conventions_sections referential \
          "${f#$REPO_DIR/} cites $sec — no such section in $doc"
        bad=1
      }
    done
  done
  [ "$bad" = "0" ] && ok "conventions section references valid"
  return 0
}

# global/AGENTS.md is what makes a skill discoverable in OTHER repos, and it lists
# them by hand. A skill missing from it ships but stays invisible. Moved from
# install.sh; the agent scan is scoped to table column 3 here rather than every
# backticked token in the file.
check_guidance_sync() {
  [ -f "$GLOBAL_MD_SRC" ] || return 0
  local listed actual missing stale bad=0

  listed="$(grep -o '^| `/[a-z0-9-]*`' "$GLOBAL_MD_SRC" | tr -d '|` /' | sort -u || true)"
  actual="$(for d in "$SKILLS_SRC"/*/; do basename "$d"; done | sort -u)"
  missing="$(comm -13 <(echo "$listed") <(echo "$actual") | tr '\n' ' ')"
  stale="$(comm -23 <(echo "$listed") <(echo "$actual") | tr '\n' ' ')"
  [ -n "${missing// }" ] && { finding check_guidance_sync doc-sync "global/AGENTS.md does not list these skills (invisible in other repos): $missing"; bad=1; }
  [ -n "${stale// }" ] && { finding check_guidance_sync doc-sync "global/AGENTS.md lists skills that no longer exist: $stale"; bad=1; }

  listed="$(awk -F'|' 'NF>3 {print $4}' "$GLOBAL_MD_SRC" | grep -o '`[a-z0-9-]*`' | tr -d '`' | sort -u || true)"
  actual="$(for f in "$AGENTS_SRC"/*.md; do basename "$f" .md; done | sort -u)"
  missing="$(comm -13 <(echo "$listed") <(echo "$actual") | tr '\n' ' ')"
  [ -n "${missing// }" ] && { finding check_guidance_sync doc-sync "global/AGENTS.md does not mention these agents: $missing"; bad=1; }

  [ "$bad" = "0" ] && ok "guidance file in sync"
  return 0
}

# hooks/suggest-skills.sh hand-lists the skills it suggests, exactly like
# global/AGENTS.md does — so it has the same staleness bug. A skill it never names
# is one the hook will never surface, which is the whole reason the hook exists.
check_hook_sync() {
  local hook="$REPO_DIR/hooks/suggest-skills.sh" listed actual missing stale bad=0
  [ -f "$hook" ] || return 0
  # Skills appear grouped inside one suggestion string — `add "/changelog and
  # /release-notes"` — so scan for every /name, not just the first per line.
  # A skill can only be flagged missing if the hook never names it anywhere, so
  # match against the real skill list rather than trying to parse the script.
  listed=""
  for n in $(for d in "$SKILLS_SRC"/*/; do basename "${d%/}"; done); do
    grep -q -- "/$n" "$hook" && listed="$listed$n
"
  done
  listed="$(printf '%s' "$listed" | sort -u)"
  actual="$(for d in "$SKILLS_SRC"/*/; do basename "${d%/}"; done | sort -u)"
  missing="$(comm -13 <(echo "$listed") <(echo "$actual") | tr '\n' ' ')"
  stale="$(comm -23 <(echo "$listed") <(echo "$actual") | tr '\n' ' ')"
  [ -n "${missing// }" ] && { finding check_hook_sync doc-sync "hooks/suggest-skills.sh never suggests these skills: $missing"; bad=1; }
  [ -n "${stale// }" ] && { finding check_hook_sync doc-sync "hooks/suggest-skills.sh suggests skills that no longer exist: $stale"; bad=1; }
  [ "$bad" = "0" ] && ok "skill-suggestion hook in sync"
  return 0
}

# Naming a skill in the hook is not the same as MATCHING it. check_hook_sync only
# proves a skill appears somewhere in the file, so a pattern can be too narrow to
# ever fire and still pass — which is what happened: the design case required the
# literal "the design", so four of one session's seven complaints about the design
# ("i dont see the design changes", "still see the old desing") never surfaced the
# gate, and two phases shipped against the wrong mockup.
#
# These cases are prompts a user actually sent. Add one whenever a real prompt
# should have fired a skill and did not.
check_hook_fires() {
  local hook="$REPO_DIR/hooks/suggest-skills.sh" bad=0 out
  [ -f "$hook" ] || return 0
  command -v jq >/dev/null 2>&1 || { ok "skill-suggestion firing (skipped: no jq)"; return 0; }

  _fires() {   # prompt, expected-skill -> 0 when the hook names it
    out=$(printf '{"prompt":%s}' "$(printf '%s' "$1" | jq -Rs .)" | bash "$hook" 2>/dev/null || true)
    case "$out" in *"$2"*) return 0 ;; *) return 1 ;; esac
  }

  while IFS='|' read -r prompt want; do
    [ -z "$prompt" ] && continue
    _fires "$prompt" "$want" || {
      finding check_hook_fires doc-sync "hook never suggests $want for: \"$prompt\""; bad=1; }
  done <<'CASES'
i dont see the design changes|/claude-design-pull
I still see the old desing, here is the new design|/claude-design-pull
none of the slide has design changes|/claude-design-pull
make it look like the mockup|/claude-design-pull
the page doesn't match the figma|/claude-design-pull
redesign the dashboard|/claude-design-pull
can you commit this|/commit-assistant
ready to push to main|/pre-push-review
CASES

  # The other half of the bargain. "design" is also a VERB, and a gate that fires
  # on "design me a schema" is one people learn to scroll past — which costs more
  # than the miss it was widened to fix. These must NOT suggest the design gate.
  while IFS='|' read -r prompt unwanted; do
    [ -z "$prompt" ] && continue
    _fires "$prompt" "$unwanted" && {
      finding check_hook_fires doc-sync "hook wrongly suggests $unwanted for: \"$prompt\""; bad=1; }
  done <<'ANTICASES'
design a database schema for invoices|/claude-design-pull
design an api for the webhook|/claude-design-pull
can you design the login screen|/claude-design-pull
designing a new caching layer|/claude-design-pull
ANTICASES

  # And it must stay silent entirely on a prompt that matches nothing — a hook
  # that fires on everything is one people learn to ignore.
  out=$(printf '{"prompt":"fix the failing test"}' | bash "$hook" 2>/dev/null || true)
  [ -n "$out" ] && { finding check_hook_fires doc-sync "hook fires on an unrelated prompt: $out"; bad=1; }

  [ "$bad" = "0" ] && ok "skill-suggestion hook fires on real prompts"
  return 0
}

# check_hook_fires proves hooks/suggest-skills.sh routes real prompts. It does not
# prove the skill *frontmatter itself* is what a model would route on — that's a
# different surface (a model reads `description`, not the hook), and with 38 skills
# two descriptions can drift close enough to collide without either ever showing up
# in the hook's own glob patterns. This closes that gap with the same free,
# deterministic, no-network style as every other check.sh check.
#
# The cases are generated, not hand-authored: scripts/gen-trigger-cases.sh pulls
# every quoted trigger phrase straight out of each skill's own `description` — the
# same words a model reads to decide it matches — so there is nothing here to keep
# in sync by hand. Regenerated into a tempdir each run, same as gen-cursor-rule.sh
# and gen-codex-agents.sh; never a committed, driftable copy.
#
# Scoring is a keyword-overlap heuristic (shared vocabulary between the prompt and
# each skill's full description), not a real model call — check.sh has no network
# and no LLM. That is a weaker signal than an actual routing decision, so it can
# only catch the regressions that show up as vocabulary drift: a description edited
# down to something too generic to match its own trigger phrases, or two skills
# whose descriptions have grown close enough to tie. A genuinely subtle routing
# ambiguity (right vocabulary, wrong intent) needs a real model in the loop —
# deliberately out of scope for this free check; see NAV-23's deferred LLM tier.
#
# Some collisions are BY DESIGN, not regressions: an umbrella and its own leaf
# dimension share vocabulary on purpose (/pre-push-review vs /review-style), as do
# tightly related PM-authoring siblings (pm-epic/pm-story/pm-task). Flagging those
# every run would make this check permanently red — the exact "fires on everything,
# people learn to ignore it" failure check_hook_fires' own comment warns about.
# Allowlist known-accepted collisions by their exact generated prompt so a NEW
# collision (an unrelated pair drifting close) still fails the build. Add an entry
# here only when a real review confirms the tie is intentional, never to silence a
# genuine regression.
DESCRIPTION_ROUTING_ALLOWED_COLLISIONS=(
  # /changelog vs /release-notes — release-notes explicitly reuses changelog's
  # section (composes with it, CLAUDE.md's workflow-class description), so
  # sharing "release notes" vocabulary is the documented relationship, not drift.
  "cut release notes"

  # /e2e-run vs /e2e-suite — leaf runner vs its own umbrella; the umbrella's whole
  # job is "run the suite" in the same words the leaf uses.
  "run the e2e tests"
  "run the browser tests"
  "run the full e2e suite"

  # /em-newsletter vs /vertical-pulse — vertical-pulse is documented as "a one-line
  # shortcut into the same pipeline" as em-newsletter, so it shares its vocabulary
  # by design.
  "do a vertical pulse"

  # /flake-watch vs /test-report — adjacent testing-class reporting skills;
  # "flake report" legitimately reads as either's territory.
  "show the flake report"

  # pm-epic vs pm-story vs pm-task — deliberately close PM-authoring siblings in
  # the same class, sharing "create a <type>" phrasing by the nature of the class.
  "create an epic"
  "draft an epic in Linear/Jira"
  "create a story in Linear/Jira"

  # /pre-push-review (umbrella) vs its own review-* leaf dimensions — the umbrella
  # runs literally these leaves, so "review my changes"/"run the tests"/"check the
  # build" is shared vocabulary between a whole and its parts by design.
  "review my changes before I push"
  "run the pre-push review"
  "check this diff for correctness"
  "scan my changes for secrets"
  "review my changes for style"
  "run the tests before I push"
  "check the build"

  # /test-data vs /test-suite-author — test-suite-author is the umbrella that
  # chains test-data as one of its stages, same umbrella/leaf relationship.
  "write fixtures for these tests"

  # /test-plan vs /flake-watch — both testing-class skills touching "what to
  # test"; genuinely adjacent territory, reviewed and accepted.
  "what should we test here"
)

check_description_routing() {
  local gen="$REPO_DIR/scripts/gen-trigger-cases.sh" bad=0
  [ -x "$gen" ] || return 0
  command -v jq >/dev/null 2>&1 || { ok "description routing (skipped: no jq)"; return 0; }

  local cases_file; cases_file="$(mktemp)"
  trap 'rm -f "$cases_file"' RETURN
  if ! "$gen" >"$cases_file" 2>/dev/null; then
    finding check_description_routing doc-sync "scripts/gen-trigger-cases.sh failed to generate cases"
    return 0
  fi

  local n_cases; n_cases="$(jq '.cases | length' "$cases_file" 2>/dev/null || echo 0)"
  if [ "$n_cases" -lt 1 ]; then
    finding check_description_routing doc-sync "gen-trigger-cases.sh produced zero cases"
    return 0
  fi

  # A description that regresses to having NO quoted trigger phrase at all removes
  # itself from the positive-case set entirely — gen-trigger-cases.sh warns and
  # skips it (it can't build a case from nothing), so the misroute check above
  # never sees it and has nothing to fail on. That is a worse silent gap than a
  # single failing case: the skill lost all its routing coverage. Catch it here by
  # requiring every skill directory to appear at least once in the generated cases.
  local uncovered
  uncovered="$(for d in "$SKILLS_SRC"/*/; do basename "${d%/}"; done | sort -u \
    | comm -23 - <(jq -r '.cases[].skill' "$cases_file" | sort -u) | tr '\n' ' ')"
  if [ -n "${uncovered// }" ]; then
    finding check_description_routing doc-sync \
      "no quoted trigger phrase found for: $uncovered — description has lost its routing vocabulary"
    bad=1
  fi

  # One "skill -> description" map, built in a single pass (no per-case re-read of
  # 38 files). All tokenizing and scoring below happens inside ONE jq invocation —
  # a bash loop calling out per (case, skill) pair is 131*38 subshells and does not
  # finish in reasonable time; jq's own string functions do the same work in one
  # process.
  local descs_file; descs_file="$(mktemp)"
  trap 'rm -f "$cases_file" "$descs_file"' RETURN
  echo "{}" >"$descs_file"
  for dir in "$SKILLS_SRC"/*/; do
    local name; name="$(basename "${dir%/}")"
    local skill_md="$dir/SKILL.md"
    [ -f "$skill_md" ] || continue
    local desc; desc="$(awk '/^---$/{n++; next} n==1 && /^description:/{sub(/^description: */,""); print; exit}' "$skill_md")"
    jq --arg k "$name" --arg v "$desc" '. + {($k): $v}' "$descs_file" >"$descs_file.tmp" && mv "$descs_file.tmp" "$descs_file"
  done

  # Stopwords kept tight and generic — this is a coverage heuristic, not an NLP
  # pipeline, and an over-tuned stopword list is how a check quietly stops meaning
  # anything.
  local result
  result="$(jq -n \
    --slurpfile cases_wrap "$cases_file" \
    --slurpfile descs_wrap "$descs_file" \
    '
    ($cases_wrap[0].cases) as $cases |
    ($descs_wrap[0]) as $descs |
    ["a","an","the","this","that","these","those","is","are","was","were","be","been",
     "being","use","uses","used","using","when","user","asks","wants","or","and","to",
     "for","with","in","of","on","at","from","into","your","you","it","its","as","not",
     "never","no","do","does","don","if"] as $stop |
    def toks: ascii_downcase
      | [scan("[a-z][a-z0-9-]{2,}")]
      | map(select(. as $t | ($stop | index($t)) | not))
      | unique;
    ($descs | with_entries(.value |= toks)) as $dtoks |
    ($cases | map(. + {ptoks: (.prompt | toks)})) as $cases2 |
    ($dtoks | keys) as $skills |
    [ $cases2[] | . as $c |
      ([ $skills[] as $s | {skill: $s, score: ([$c.ptoks[] as $t | select($dtoks[$s] | index($t))] | length)} ]) as $scored |
      (reduce $scored[] as $x (0; if $x.score > . then $x.score else . end)) as $best |
      ([ $scored[] | select(.score == $best) | .skill ]) as $top |
      {prompt: $c.prompt, skill: $c.skill, top: $top, misrouted: ($top | index($c.skill) | not),
       collided: (($top | index($c.skill)) and ($top | length) > 1)}
    ] as $results |
    {
      misrouted: [ $results[] | select(.misrouted) ],
      collided:  [ $results[] | select(.collided) ],
    }
    ')"

  local allowed_json="[]"
  local p
  for p in "${DESCRIPTION_ROUTING_ALLOWED_COLLISIONS[@]}"; do
    allowed_json="$(jq --arg p "$p" '. + [$p]' <<<"$allowed_json")"
  done
  result="$(jq --argjson allowed "$allowed_json" \
    '.collided |= [ .[] | select(.prompt as $p | ($allowed | index($p)) | not) ]' <<<"$result")"

  local n_mis n_col
  n_mis="$(jq '.misrouted | length' <<<"$result")"
  n_col="$(jq '.collided | length' <<<"$result")"

  if [ "$n_mis" -gt 0 ]; then
    while IFS=$'\t' read -r prompt expect top; do
      finding check_description_routing doc-sync \
        "\"$prompt\" expected to route to $expect, top-scoring skill(s) instead: $top"
    done < <(jq -r '.misrouted[] | [.prompt, .skill, (.top | join(" "))] | @tsv' <<<"$result")
    bad=1
  fi

  if [ "$n_col" -gt 0 ]; then
    while IFS=$'\t' read -r prompt expect top; do
      finding check_description_routing doc-sync \
        "\"$prompt\" (expected $expect) ties with another skill's description and isn't in the allowlist: $top"
    done < <(jq -r '.collided[] | [.prompt, .skill, (.top | join(" "))] | @tsv' <<<"$result")
    bad=1
  fi

  [ "$bad" = "0" ] && ok "skill description routing: $n_cases generated cases, no misroutes or unallowed collisions"
  return 0
}

# A skill's scripts/ dir ships executable code — the SKILL.md/agent prose contract
# checks elsewhere in this file never exercise it, only describe it. A test_*.py
# alongside it (tempdir-fixture, exit 0/1, no network — same discipline as
# tech-blog's test_make_cover.py / test_rasterize_svg.py / test_publish_devto.py)
# is what actually proves the script does what its skill claims. This only checks
# a test FILE exists per scripts/ dir, not that its assertions are any good — that
# part is still a human/reviewer judgment call, same as every other check.sh check
# that verifies structure rather than content quality.
check_script_self_tests() {
  local bad=0 dir name py_count test_count
  for dir in "$SKILLS_SRC"/*/scripts/; do
    [ -d "$dir" ] || continue
    name="$(basename "$(dirname "$dir")")"
    py_count="$(find "$dir" -maxdepth 1 -name '*.py' ! -name 'test_*.py' 2>/dev/null | wc -l | tr -d ' ')"
    [ "$py_count" -gt 0 ] || continue  # a scripts/ dir with no .py has nothing this check can test
    test_count="$(find "$dir" -maxdepth 1 -name 'test_*.py' 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$test_count" -lt 1 ]; then
      finding check_script_self_tests script-coverage \
        "skills/$name/scripts/ has $py_count script(s) but no test_*.py self-test"
      bad=1
    fi
  done
  [ "$bad" = "0" ] && ok "every skill scripts/ dir with .py files has a test_*.py"
  return 0
}

# Every other check.sh check validates a skill's STATED contract (tools:
# frontmatter, "never runs git" prose, cost/progress citations). None of them scan
# what a skill's files would actually DO if the agent-code inside ran — an install
# lure, a hidden network call, or credential-reading code would pass every existing
# check as long as the prose around it reads correctly. This closes that gap.
#
# Two lenses, because "network call" and "install lure" need different signal
# shapes and different false-positive tolerance:
#
#   A. Code files (scripts/*.py/*.js/*.sh) — cross-reference against the skill's
#      own `## Dependencies` table (the same table check_dependencies already
#      requires). A declared network call (e.g. publish-devto.py's Dev.to REST API,
#      documented in tech-blog/SKILL.md's Dependencies table) is fine; an
#      UNDECLARED one is the finding. A fetch-pipe-execute shape in CODE has no
#      legitimate reading regardless of declaration — always BLOCK.
#
#   B. Prose (SKILL.md/agents/*.md) — a fetch-pipe-execute shape here is almost
#      always a human-facing install instruction (review-secrets prints one for
#      trufflehog, inside a block explicitly followed by "do not install anything
#      yourself"). Only BLOCK when that "for the human, not the agent" framing is
#      ABSENT nearby — otherwise every install-instructions block in the repo would
#      false-positive, which is worse than missing a genuine lure (§C: a check that
#      fires on everything is one people learn to ignore).
check_artifact_security() {
  local bad=0 f base
  local fetch_exec_re='(curl|wget)[^|]*(\|\s*(sh|bash|zsh)\b|-O-[^|]*\|)'
  local human_framing_re='do not install|only the user install|for the user to|have the user|print the install'

  # --- Lens A: code files ---
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    # Fetch-pipe-execute in code: no legitimate reading, always BLOCK.
    if grep -qEi "$fetch_exec_re" "$f" 2>/dev/null; then
      finding check_artifact_security install-lure \
        "$f contains a fetch-then-execute pattern (curl/wget piped to a shell) — remove it, this is never legitimate inside a skill's own script"
      bad=1
    fi
    # Undeclared network call: the script imports/calls a network primitive, but
    # its skill's SKILL.md has no Dependencies table mentioning network/API use.
    if grep -qE '(import (urllib|requests|http\.client)|fetch\(|XMLHttpRequest|axios\.)' "$f" 2>/dev/null; then
      local skill_dir skill_md skill_name
      skill_dir="$(dirname "$(dirname "$f")")"
      skill_name="$(basename "$skill_dir")"
      skill_md="$skill_dir/SKILL.md"
      if [ -f "$skill_md" ]; then
        grep -q '^## Dependencies' "$skill_md" || {
          finding check_artifact_security undeclared-network \
            "$f makes a network call but skills/$skill_name/SKILL.md has no '## Dependencies' table declaring it"
          bad=1
        }
      fi
    fi
  done < <(find "$SKILLS_SRC" -path '*/scripts/*' \( -name '*.py' -o -name '*.js' -o -name '*.sh' \) ! -name 'test_*' 2>/dev/null)

  # --- Lens B: prose (SKILL.md + agents/*.md) ---
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    grep -qEi "$fetch_exec_re" "$f" 2>/dev/null || continue
    # Human framing nearby (anywhere in the file — these blocks are short and the
    # framing is usually a line or two away, not always adjacent) means this is a
    # documented install step, not an instruction for the agent to execute.
    grep -qEi "$human_framing_re" "$f" 2>/dev/null && continue
    finding check_artifact_security install-lure \
      "$f contains a fetch-then-execute pattern with no nearby human-facing framing (e.g. \"do not install anything yourself\") — confirm this is documentation, not an instruction to execute"
    bad=1
  done < <(find "$SKILLS_SRC" -maxdepth 2 -name 'SKILL.md'; find "$AGENTS_SRC" -maxdepth 1 -name '*.md' 2>/dev/null)

  [ "$bad" = "0" ] && ok "artifact security scan: no install lures, undeclared network calls found"
  return 0
}

# An agent named in the docs but deleted from the repo — the half install.sh's
# sync check never looked for.
check_stale_agents() {
  local listed a bad=0
  [ -f "$GLOBAL_MD_SRC" ] || return 0
  listed="$(awk -F'|' 'NF>3 {print $4}' "$GLOBAL_MD_SRC" | grep -o '`[a-z0-9-]*`' | tr -d '`' | sort -u || true)"
  for a in $listed; do
    [ -f "$AGENTS_SRC/$a.md" ] || {
      finding check_stale_agents doc-sync "global/AGENTS.md cites agent '$a' — no agents/$a.md"
      bad=1
    }
  done
  [ "$bad" = "0" ] && ok "no stale agent references"
  return 0
}

# Both CLAUDE.md files state the counts in prose. Prose drifts silently.
# Codex TRUNCATES AGENTS.md past 32 KiB, and truncation is silent — the guidance
# simply stops applying part-way through, with nothing to notice. The file is well
# under today, so this is a tripwire for the edit that pushes it over rather than a
# current problem.
# A count drawn into an SVG goes stale the moment a skill is added, gives no
# signal that it has, and needs the diagram redrawn to correct. The same number in
# a caption is one edit — and on the docs site it is generated from the file tree.
# So: tallies live under the image, never inside it. This catches the next diagram
# that tries, by looking for the current skill/agent counts as rendered text.
check_diagram_counts() {
  local f bad=0 n_skills n_agents n_gates n_scans
  n_skills="$(ls -d "$SKILLS_SRC"/*/ 2>/dev/null | wc -l | tr -d ' ')"
  n_agents="$(ls "$AGENTS_SRC"/*.md 2>/dev/null | wc -l | tr -d ' ')"
  n_gates="$(grep -l '^subclass: gate' "$SKILLS_SRC"/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')"
  n_scans="$(grep -l '^subclass: scan' "$SKILLS_SRC"/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')"
  for f in "$REPO_DIR"/docs/architecture/*.svg; do
    [ -f "$f" ] || continue
    # Only flag the two totals that track the file tree. Structural numbers a
    # diagram legitimately states ("1 level deep", "0 commits", "caps at 2") are
    # design facts, not tallies, and must not trip this.
    if grep -qE ">($n_skills|$n_agents)<|\b$n_skills skills\b|\b$n_agents agents\b|\b$n_gates gates\b|\b$n_scans scans\b" "$f"; then
      finding check_diagram_counts doc-sync \
        "${f#$REPO_DIR/} has a skill/agent count drawn into it — put tallies in the caption, where they are generated and cannot go stale"
      bad=1
    fi
  done
  [ "$bad" = "0" ] && ok "diagrams carry no file-tree counts"
  return 0
}

# Codex reads agents as TOML, so install.sh generates them rather than linking.
# A generator that emits malformed TOML fails silently — Codex just skips the
# agent, exactly as it skipped the two skills with invalid YAML. Generate into a
# temp dir and parse the result.
check_codex_agent_generation() {
  local tmp n_md n_toml bad=0
  [ -x "$REPO_DIR/scripts/gen-codex-agents.sh" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  tmp="$(mktemp -d)" || return 0
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  if ! "$REPO_DIR/scripts/gen-codex-agents.sh" "$tmp" >/dev/null 2>&1; then
    finding check_codex_agent_generation structural \
      "scripts/gen-codex-agents.sh failed — Codex would get skills but no agents"
    return 0
  fi

  n_md="$(ls "$AGENTS_SRC"/*.md 2>/dev/null | wc -l | tr -d ' ')"
  n_toml="$(ls "$tmp"/*.toml 2>/dev/null | wc -l | tr -d ' ')"
  [ "$n_md" = "$n_toml" ] || {
    finding check_codex_agent_generation structural \
      "Codex agent generation produced $n_toml .toml for $n_md agents"
    bad=1
  }

  # Valid TOML, and every required Codex field present and non-empty.
  python3 - "$tmp" <<'PY' || bad=1
import sys, glob, os, tomllib
bad = []
for p in sorted(glob.glob(f"{sys.argv[1]}/*.toml")):
    try:
        d = tomllib.load(open(p, "rb"))
    except Exception as e:
        bad.append(f"{os.path.basename(p)}: {e}"); continue
    for k in ("name", "description", "developer_instructions"):
        if not d.get(k):
            bad.append(f"{os.path.basename(p)}: missing or empty '{k}'")
for b in bad:
    print(f"  ! generated Codex agent {b}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY
  [ "$bad" = "0" ] && ok "Codex agent generation produces valid TOML ($n_toml agents)"
  return 0
}

# Cursor's own create-rule skill says rules should stay "under 50 lines" and be
# "concise and to the point". Our rule is generated, so it can quietly grow past
# that as skills are added — an always-on rule costs context on every request.
# The wrapper exists to turn a verdict into an exit code, because `claude -p`
# exits 0 whether the review passed or blocked. That mapping is the whole product
# and it is runner-neutral, so assert it against stub CLIs rather than trusting it
# — an absent verdict must read as error (2), never as pass.
check_review_exit_codes() {
  local tmp bad=0 v want got
  [ -x "$REPO_DIR/bin/nj-agents-review" ] || return 0
  tmp="$(mktemp -d)" || return 0
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  for v in "BLOCK:1" "PASS:0" "WARN:0" "NOVERDICT:2"; do
    want="${v##*:}"; v="${v%%:*}"
    if [ "$v" = "NOVERDICT" ]; then
      printf '#!/bin/sh\necho "the review did not reach a verdict"\n' > "$tmp/stub"
    else
      printf '#!/bin/sh\necho "Overall: %s"\n' "$v" > "$tmp/stub"
    fi
    chmod +x "$tmp/stub"
    got=0
    NJ_AGENT_CMD="$tmp/stub" "$REPO_DIR/bin/nj-agents-review" >/dev/null 2>&1 || got=$?
    [ "$got" = "$want" ] || {
      finding check_review_exit_codes structural \
        "bin/nj-agents-review: a '$v' verdict exited $got, expected $want (CONVENTIONS.md §5)"
      bad=1
    }
  done
  [ "$bad" = "0" ] && ok "review verdict maps to the right exit code on any runner"
  return 0
}

check_cursor_rule() {
  local tmp lines
  [ -x "$REPO_DIR/scripts/gen-cursor-rule.sh" ] || return 0
  tmp="$(mktemp -d)" || return 0
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  if ! "$REPO_DIR/scripts/gen-cursor-rule.sh" "$tmp" >/dev/null 2>&1; then
    finding check_cursor_rule structural \
      "scripts/gen-cursor-rule.sh failed — Cursor would not know the toolkit exists"
    return 0
  fi
  [ -f "$tmp/nj-agents.mdc" ] || {
    finding check_cursor_rule structural "gen-cursor-rule.sh wrote no nj-agents.mdc"
    return 0
  }
  # Frontmatter must be real, or Cursor treats it as a plain file.
  head -1 "$tmp/nj-agents.mdc" | grep -q '^---$' || {
    finding check_cursor_rule structural "the generated Cursor rule has no YAML frontmatter"
    return 0
  }
  lines="$(wc -l < "$tmp/nj-agents.mdc" | tr -d ' ')"
  if [ "$lines" -gt 50 ]; then
    finding check_cursor_rule structural \
      "the generated Cursor rule is $lines lines — over Cursor's own 50-line guidance for an always-on rule. Make it point at more and state less."
    return 0
  fi
  ok "Cursor rule generates and fits its 50-line budget ($lines lines)"
  return 0
}

check_guidance_size() {
  local bytes limit=32768
  [ -f "$GLOBAL_MD_SRC" ] || return 0
  bytes="$(wc -c < "$GLOBAL_MD_SRC" | tr -d ' ')"
  if [ "$bytes" -gt "$limit" ]; then
    finding check_guidance_size structural \
      "global/AGENTS.md is ${bytes} bytes — over Codex's ${limit}-byte limit, so it will be silently truncated there"
    return 0
  fi
  ok "guidance file fits Codex's 32 KiB limit ($((bytes / 1024)) KiB used)"
  return 0
}

# The installer's whole premise is that ONE clone feeds every runner via symlinks.
# That is cheap to assert for real — install into a temp dir and look — and it is
# the kind of claim that rots silently, so assert it rather than trusting the docs.
# The testing skills claim to DETECT a runner rather than assume one (§T5). That
# claim is cheap to assert and expensive to leave untested: a skill hardcoded to
# Playwright passes every review and fails silently in a Cypress repo.
#
# These assert the fixtures give detection something real to find. They do not run
# a suite — what needs proving here is what the skills decide, not whether a
# browser launches, and installing browser binaries would make this slow and
# network-dependent for no extra signal.
# A skill that spawns agents must decide there is work to do BEFORE spawning, and
# must call the empty case a PASS. Two failures otherwise, both silent:
#
#   - five agents dispatched to confirm a clean tree, at real cost
#   - "nothing to review" with no verdict, which bin/nj-agents-review maps to
#     exit 2 — so a clean working tree fails a pre-push hook
#
# Only spawning skills are held to this: a skill with no fleet has nothing to
# short-circuit, and its empty case costs nothing.
check_empty_input_pass() {
  local d name f bad=0
  for d in "$SKILLS_SRC"/*/; do
    name="$(basename "${d%/}")"; f="${d%/}/SKILL.md"
    [ -f "$f" ] || continue
    has "$f" 'get a yes before\|and get a yes' i || continue   # spawning skills only
    # Match the SHAPE — "no input → stop before spawning" — not one phrasing.
    # Each skill's empty case is different ("nothing to describe", "isn't
    # published", "no source to scan"), and a narrow pattern would push authors
    # to paste a magic phrase rather than think about their own empty case.
    has "$f" 'nothing to [a-z]*\|no .* to [a-z]*\|working tree clean\|is.*empty\|SKIP\|before spawning' i || {
      finding check_empty_input_pass referential \
        "skills/$name spawns agents but never says what happens when there is nothing to do — §U requires a PASS before any dispatch, not a spawned agent and not an error"
      bad=1
    }
  done
  [ "$bad" = "0" ] && ok "spawning skills handle an empty input without dispatching"
  return 0
}

check_e2e_fixtures() {
  local f bad=0
  f="$REPO_DIR/tests/fixtures"
  [ -x "$f/../fixtures/make.sh" ] || return 0
  # Fixtures are generated and gitignored, so a fresh clone has none. Build them
  # if they are absent rather than reporting a false gap.
  # Build only when NOTHING is there — a fresh clone. Deliberately not "rebuild if
  # any one fixture is missing": that makes a deleted fixture unobservable, because
  # make.sh restores it before the assertions below can see it is gone. Verified by
  # trying it — the e2e-python assertion silently stopped biting.
  #
  # Cost of this choice: adding a fixture needs `tests/fixtures/make.sh` run once by
  # hand in an existing tree. The assertions below then say exactly which is missing.
  [ -d "$f/e2e-playwright" ] || "$f/make.sh" >/dev/null 2>&1 || {
    finding check_e2e_fixtures structural "tests/fixtures/make.sh failed — the E2E fixtures cannot be built"
    return 0
  }

  # Two different stacks. One would pass against a hardcoded runner; two is the
  # minimum that shows detection is real.
  [ -f "$f/e2e-playwright/playwright.config.ts" ] || {
    finding check_e2e_fixtures structural "fixture e2e-playwright has no playwright config — nothing for §T5 detection to find"
    bad=1
  }
  [ -f "$f/e2e-cypress/cypress.config.js" ] || {
    finding check_e2e_fixtures structural "fixture e2e-cypress has no cypress config — detection is only proven by a second stack"
    bad=1
  }
  # The SKIP path. A silent pass here is the worst of the three outcomes, so the
  # fixture that produces it has to exist.
  if [ -d "$f/e2e-none" ]; then
    ls "$f/e2e-none"/*.config.* >/dev/null 2>&1 && {
      finding check_e2e_fixtures structural "fixture e2e-none has a runner config — it exists to prove the §T5 SKIP path"
      bad=1
    }
  else
    finding check_e2e_fixtures structural "fixture e2e-none is missing — nothing exercises the §T5 SKIP path"
    bad=1
  fi
  # /test-author must flag brittle locators, so a brittle one has to be present.
  grep -rq 'nth-child' "$f/e2e-playwright/e2e" 2>/dev/null || {
    finding check_e2e_fixtures structural "no brittle locator in the playwright fixture — /test-author's flagging has nothing to catch"
    bad=1
  }

  # A runner that DETECTS cleanly and resolves to zero specs (GitHub #9). Distinct
  # from e2e-none: there nothing is found and SKIP is obvious. Here detection
  # succeeds and the suite is empty — the shape that reports green over a suite
  # that no longer exists, if the skill trusts the runner's exit code.
  [ -f "$f/e2e-stale-config/tests/playwright.config.js" ] || {
    finding check_e2e_fixtures structural \
      "fixture e2e-stale-config has no config — the detects-but-resolves-to-nothing path is unverifiable"
    bad=1
  }
  [ -d "$f/e2e-stale-config/tests/specs" ] && {
    finding check_e2e_fixtures structural \
      "fixture e2e-stale-config HAS a specs dir — its whole point is that testDir does not resolve"
    bad=1
  }
  # A real suite no JS probe can see. Detection that only knows playwright/cypress
  # reports 'no runner' on a repo with a working suite.
  [ -f "$f/e2e-python/tests/verify_login.py" ] || {
    finding check_e2e_fixtures structural \
      "fixture e2e-python has no verify_*.py — non-JS detection is proven by nothing"
    bad=1
  }
  [ -f "$f/e2e-python/AGENTS.md" ] || {
    finding check_e2e_fixtures structural \
      "fixture e2e-python has no AGENTS.md — the documented-command probe has nothing to find"
    bad=1
  }

  # The skill must actually say it checks a detected runner resolves to specs.
  # Without this the fixtures above exist and nothing consults them.
  local sk="$SKILLS_SRC/e2e-run/SKILL.md"
  if [ -f "$sk" ]; then
    has "$sk" 'resolves to\|resolve to.*spec\|0 specs\|zero.*spec' i || {
      finding check_e2e_fixtures referential \
        "skills/e2e-run does not say a detected runner is verified to resolve to specs — a stale config would be run as if live (GitHub #9)"
      bad=1
    }
    has "$sk" 'verify_\|pytest\|non-JS\|not only a JS' i || {
      finding check_e2e_fixtures referential \
        "skills/e2e-run probes only JS runners — a pytest or verify_*.py suite is invisible to it (GitHub #9)"
      bad=1
    }
  fi

  [ "$bad" = "0" ] && ok "E2E fixtures cover JS, non-JS, no-runner, and stale-config detection"
  return 0
}

check_push_gate() {
  local h="$REPO_DIR/hooks/git/pre-push-e2e" bad=0
  [ -f "$h" ] || return 0     # not built yet — not a finding

  [ -x "$h" ] || {
    finding check_push_gate structural \
      "hooks/git/pre-push-e2e is not executable — git silently ignores a non-executable hook, so the gate would be installed and dead"
    bad=1
  }

  # The gate must SPEND NOTHING. check.yml:7 and hooks/git/pre-push:8 both record
  # that per-push LLM spend is unacceptable; a hook that calls a wrapper would
  # reverse that decision without anyone deciding to.
  # Strip comments FIRST, then look. The earlier spelling asked "does any commented
  # line mention the wrapper?" — and the file's own header explains at length why it
  # must not call one, so that guard passed no matter what the code did. Verified by
  # planting a real call and watching it go undetected.
  if grep -vE '^\s*#' "$h" | grep -qE '(nj-agents-e2e|nj-agents-review|claude -p|codex exec)'; then
    finding check_push_gate behavioural \
      "hooks/git/pre-push-e2e invokes an LLM wrapper — the push gate must spend nothing (see check.yml:7, hooks/git/pre-push:8)"
    bad=1
  fi

  # GitHub #9 lives in TWO places now: the skill text, and this hook. The hook is
  # the one that actually gates a push, so if they drift the hook is what ships.
  has "$h" 'resolves to 0\|0 specs\|Total: 0 tests' i || {
    finding check_push_gate referential \
      "hooks/git/pre-push-e2e does not check that a detected runner resolves to specs — a stale config would pass the gate (GitHub #9)"
    bad=1
  }

  # A gate that goes quiet is indistinguishable from one that was uninstalled.
  has "$h" 'not configured' i || {
    finding check_push_gate behavioural \
      "hooks/git/pre-push-e2e can exit without saying why — a silent no-op reads as a passing gate"
    bad=1
  }

  [ "$bad" = "0" ] && ok "push gate spends nothing, checks specs resolve, and never exits silently"
  return 0
}

check_run_harness() {
  local h="$REPO_DIR/bin/nj-run" t="$REPO_DIR/tests/test-nj-run.sh"
  [ -f "$h" ] || return 0     # not yet built — not a finding

  [ -x "$h" ] || {
    finding check_run_harness structural \
      "bin/nj-run is not executable — a skill invoking it gets a permission error"
  }

  # The harness records cost, subagent lifecycle and the log for the WHOLE class
  # (§T13). If its own behavioural checks are absent or failing, every skill that
  # reports a cost or a verdict through it is reporting something unverified.
  [ -x "$t" ] || {
    finding check_run_harness structural \
      "bin/nj-run exists but tests/test-nj-run.sh does not — §T10/§T11/§T12 are asserted by nothing"
    return 0
  }
  if ! "$t" >/dev/null 2>&1; then
    finding check_run_harness behavioural \
      "tests/test-nj-run.sh is failing — run it directly; the run harness is what every testing skill reports cost and verdicts through"
    return 0
  fi
  # §T14: the ledger must have a WRITER, and something must call it. /flake-watch
  # and /test-triage both read it, and both degrade silently without it —
  # /flake-watch reports "insufficient history" forever, and /test-triage is barred
  # from calling `flake` without history, so it files genuine flakes as defects.
  # Neither errors, which is why this needs a check rather than a bug report.
  grep -q 'cmd_ledger' "$h" || {
    finding check_run_harness structural \
      "bin/nj-run has no ledger writer — §T14's ledger is read by /flake-watch and /test-triage and written by nothing"
    return 0
  }
  local er="$SKILLS_SRC/e2e-run/SKILL.md"
  if [ -f "$er" ] && ! has "$er" 'ledger record' i; then
    finding check_run_harness referential \
      "skills/e2e-run never calls 'nj-run ledger record' — the ledger stays empty, so /test-triage can never reach a flake verdict"
  fi

  ok "run harness passes its own §T10/§T11/§T12 checks, and §T14's ledger has a writer"
  return 0
}

check_installer_runners() {
  local tmp bad=0 r dir guide
  command -v mktemp >/dev/null 2>&1 || return 0
  tmp="$(mktemp -d)" || return 0
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  # install.sh runs check.sh when it finishes; without this guard that would
  # recurse forever, since we are check.sh calling install.sh.
  export NJ_AGENTS_NO_CHECK=1

  for r in claude codex gemini agents; do
    if ! "$REPO_DIR/install.sh" --runner "$r" --project "$tmp" >/dev/null 2>&1; then
      finding check_installer_runners structural "install.sh --runner $r failed"
      bad=1; continue
    fi
    dir="$tmp/.$r"
    [ -L "$dir/skills/changelog" ] || {
      finding check_installer_runners structural "install.sh --runner $r: skills not linked"
      bad=1
    }
    # Every runner must resolve to the SAME source file — that is the property
    # that makes one clone serve all of them.
    if [ "$(readlink "$dir/skills/changelog" 2>/dev/null)" != "$SKILLS_SRC/changelog" ]; then
      finding check_installer_runners structural \
        "install.sh --runner $r: skill link does not point back into this repo"
      bad=1
    fi
  done

  # Guidance lands under the filename each runner actually reads.
  for r in "claude:CLAUDE.md" "codex:AGENTS.md" "gemini:GEMINI.md" "agents:AGENTS.md"; do
    dir="$tmp/.${r%%:*}"; guide="${r##*:}"
    [ -L "$dir/$guide" ] || {
      finding check_installer_runners structural \
        "install.sh --runner ${r%%:*}: no $guide guidance link"
      bad=1
    }
  done

  # An unknown runner must fail loudly, not install somewhere nothing reads.
  if "$REPO_DIR/install.sh" --runner nonesuch --project "$tmp" >/dev/null 2>&1; then
    finding check_installer_runners structural "install.sh accepted an unknown --runner"
    bad=1
  fi

  [ "$bad" = "0" ] && ok "installer serves every runner from one clone"
  return 0
}

check_counts() {
  local s a f stated bad=0
  s="$(ls -d "$SKILLS_SRC"/*/ | wc -l | tr -d ' ')"
  a="$(ls "$AGENTS_SRC"/*.md | wc -l | tr -d ' ')"
  for f in "$REPO_MD_SRC" "$GLOBAL_MD_SRC"; do
    [ -f "$f" ] || continue
    stated="$(grep -o '[0-9]\{1,3\} skills[^.]*[0-9]\{1,3\} agents' "$f" | head -1 || true)"
    [ -n "$stated" ] || continue
    case "$stated" in
      *"$s skills"*"$a agents"*) ;;
      *) finding check_counts doc-sync "${f#$REPO_DIR/} says '$stated' — actual: $s skills, $a agents"; bad=1 ;;
    esac
  done
  [ "$bad" = "0" ] && ok "documented counts match ($s skills, $a agents)"
  return 0
}

[ "$JSON" = "1" ] || echo "Checking nj-agents ..."

check_vendor_neutral
check_frontmatter_yaml
check_skill_frontmatter
check_agent_frontmatter
check_authorship
check_agent_references
check_class_conventions
check_conventions_reachable
check_class_contract
check_universal_rules
check_dependencies
check_cost_control
check_progress_reporting
check_conventions_sections
check_guidance_sync
check_hook_sync
check_hook_fires
check_description_routing
check_script_self_tests
check_artifact_security
check_stale_agents
check_codex_agent_generation
check_review_exit_codes
check_cursor_rule
check_guidance_size
check_diagram_counts
check_empty_input_pass
check_e2e_fixtures
check_run_harness
check_push_gate
check_installer_runners
check_counts

if [ "$JSON" = "1" ]; then
  printf '{"findings":[%s],"count":%s}\n' "${JSON_ROWS%,}" "$FINDINGS"
elif [ "$FINDINGS" = "0" ]; then
  echo "All checks passed."
else
  echo "$FINDINGS finding(s)." >&2
fi

# Advisory by default so this can never break an install; --strict is the gate.
[ "$STRICT" = "1" ] && [ "$FINDINGS" -gt 0 ] && exit 1
exit 0
