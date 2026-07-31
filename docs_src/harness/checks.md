# What is checked

`./check.sh` runs 14 checks. Advisory by default so it can never break an install;
`--strict` turns any finding into exit 1, and that is what CI uses.

```bash
./check.sh              # report findings, exit 0
./check.sh --strict     # exit 1 on any finding  (CI)
./check.sh --json       # machine-readable findings
```

## The checks

| Check | Catches | Kind |
|---|---|---|
| `check_skill_frontmatter` | Missing key, `name` ≠ directory, non-semver version, unknown class | structural |
| `check_agent_frontmatter` | Missing key, `name` ≠ filename | structural |
| `check_authorship` | A skill or agent with no `author:` | structural |
| `check_agent_references` | A skill spawning an agent that does not exist; an agent nothing spawns | referential |
| `check_class_conventions` | A class that cites the wrong conventions file, or none | referential |
| `check_conventions_reachable` | A skill with no `readlink -f` resolution block | referential |
| `check_class_contract` | **A skill that quietly opted out of its class's safety rails** | referential |
| `check_cost_control` | A spawning skill that declares no cost shape | referential |
| `check_progress_reporting` | A spawning skill that never announces what it dispatched | referential |
| `check_conventions_sections` | A citation like `§A9` pointing at a heading that does not exist | referential |
| `check_guidance_sync` | A skill missing from `global/AGENTS.md`, or listed after deletion | doc-sync |
| `check_hook_sync` | A skill the suggestion hook never suggests | doc-sync |
| `check_stale_agents` | An agent named in the docs but deleted from the repo | doc-sync |
| `check_counts` | Prose counts drifting from reality | doc-sync |

## The one that matters most

Every other check catches a typo. `check_class_contract` catches **a skill that looks
fine but silently opted out of its own class's safety rails** — a review skill with no
CI mode, an authoring skill that never proposes the commit.

That is the exact failure this harness exists to close, so it is worth understanding
what it keys off.

## Scaffolding, not just validation

A validator alone is a wall. The generator is the door:

```bash
./check.sh --new-skill <name> --class review|authoring|workflow|pm|social
./check.sh --new-agent <name>
```

Both scaffold from `templates/`, fill `author` from `git config user.name`, refuse to
overwrite, and then **immediately run the validator** — so an author sees what is
still missing now rather than at review time.

## Where it runs

- **CI** — `.github/workflows/check.yml`, on every push and pull request
- **Locally** — `./install.sh --git-hooks` installs a `pre-push` hook running the same
  checks in about a second
- **On install** — `./install.sh` reports findings but never fails, so a validator
  problem can never block installation
