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
#   ./check.sh --new-skill NAME --class review|authoring|workflow|pm|social
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
GLOBAL_MD_SRC="$REPO_DIR/global/CLAUDE.md"
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
      review|authoring|workflow|pm|social) ;;
      *) echo "  ! --class must be one of: review authoring workflow pm social" >&2; exit 2 ;;
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
      review|authoring|workflow|pm|social|"") ;;
      *) finding check_skill_frontmatter structural "skills/$name: unknown class '$val'"; bad=1 ;;
    esac
  done
  [ "$bad" = "0" ] && ok "skill frontmatter ok ($(ls -d "$SKILLS_SRC"/*/ | wc -l | tr -d ' ') skills)"
  return 0
}

check_agent_frontmatter() {
  local f name key val bad=0
  for f in "$AGENTS_SRC"/*.md; do
    name="$(basename "$f" .md)"
    # No `model:` — an agent inherits the session's model, so an Opus session gets
    # Opus subagents. Pinning one in the file silently overrides the user's choice.
    # If an agent ever needs a specific tier, it states why in its own body.
    for key in name description color; do
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
  local f name refs r bad=0
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
  for f in "$AGENTS_SRC"/*.md; do
    name="$(basename "$f" .md)"
    grep -rqF "\`$name\`" "$SKILLS_SRC"/ || {
      finding check_agent_references referential "agents/$name.md is an orphan — no SKILL.md references it"
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
      workflow)
        has "$f" 'never .*git\|never push\|never runs git' i || {
          finding check_class_contract referential \
            "skills/$name (workflow) never states that it does not run git"
          bad=1
        } ;;
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
    for sec in $(grep -o '§[AP]\{0,1\}[0-9]\{1,2\}' "$f" 2>/dev/null | sort -u); do
      num="${sec#§}"
      case "$num" in
        A*) doc="CONVENTIONS-authoring.md" ;;
        P*) doc="CONVENTIONS-pm.md" ;;
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

# global/CLAUDE.md is what makes a skill discoverable in OTHER repos, and it lists
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
  [ -n "${missing// }" ] && { finding check_guidance_sync doc-sync "global/CLAUDE.md does not list these skills (invisible in other repos): $missing"; bad=1; }
  [ -n "${stale// }" ] && { finding check_guidance_sync doc-sync "global/CLAUDE.md lists skills that no longer exist: $stale"; bad=1; }

  listed="$(awk -F'|' 'NF>3 {print $4}' "$GLOBAL_MD_SRC" | grep -o '`[a-z0-9-]*`' | tr -d '`' | sort -u || true)"
  actual="$(for f in "$AGENTS_SRC"/*.md; do basename "$f" .md; done | sort -u)"
  missing="$(comm -13 <(echo "$listed") <(echo "$actual") | tr '\n' ' ')"
  [ -n "${missing// }" ] && { finding check_guidance_sync doc-sync "global/CLAUDE.md does not mention these agents: $missing"; bad=1; }

  [ "$bad" = "0" ] && ok "guidance file in sync"
  return 0
}

# hooks/suggest-skills.sh hand-lists the skills it suggests, exactly like
# global/CLAUDE.md does — so it has the same staleness bug. A skill it never names
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

# An agent named in the docs but deleted from the repo — the half install.sh's
# sync check never looked for.
check_stale_agents() {
  local listed a bad=0
  [ -f "$GLOBAL_MD_SRC" ] || return 0
  listed="$(awk -F'|' 'NF>3 {print $4}' "$GLOBAL_MD_SRC" | grep -o '`[a-z0-9-]*`' | tr -d '`' | sort -u || true)"
  for a in $listed; do
    [ -f "$AGENTS_SRC/$a.md" ] || {
      finding check_stale_agents doc-sync "global/CLAUDE.md cites agent '$a' — no agents/$a.md"
      bad=1
    }
  done
  [ "$bad" = "0" ] && ok "no stale agent references"
  return 0
}

# Both CLAUDE.md files state the counts in prose. Prose drifts silently.
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
check_stale_agents
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
